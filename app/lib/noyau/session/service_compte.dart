import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/client_api.dart';
import '../config.dart';
import '../crypto/base64url.dart';
import '../crypto/chiffrement.dart';
import '../securite/coffre.dart';
import '../stockage/base_locale.dart';

enum ModeSession {
  chargement,

  /// Pas de compte : tout reste sur l'appareil (UC-A0).
  visiteur,

  /// Connecté, mais l'appareil attend d'être déverrouillé (I11).
  enAttente,

  /// Clé maître disponible : synchro, fichiers, partage.
  actif,
}

@immutable
class EtatSession {
  const EtatSession(this.mode, {this.compte, this.appareil});

  final ModeSession mode;
  final Map<String, dynamic>? compte;
  final Map<String, dynamic>? appareil;

  bool get connecte => mode == ModeSession.enAttente || mode == ModeSession.actif;
  bool get cleRecuperationAConfirmer => compte != null && compte!['cleRecuperationConfirmee'] != true;
}

/// Résultat de la vérification de l'e-mail : la clé de récupération à montrer UNE fois.
class InscriptionTerminee {
  InscriptionTerminee(this.cleRecuperationAffichee);
  final String cleRecuperationAffichee;
}

/// Comptes, appareils et clés (contrats 2.1 à 2.4), côté app.
class ServiceCompte extends ChangeNotifier {
  ServiceCompte(this.api, this.crypto, this.coffre, this.base) {
    api.surSessionInvalide = () => unawaited(_sessionPerdue());
  }

  final ClientApi api;
  final Chiffrement crypto;
  final Coffre coffre;
  final BaseLocale base;

  EtatSession _etat = const EtatSession(ModeSession.chargement);
  EtatSession get etat => _etat;
  Uint8List? _cleMaitre;
  Uint8List? get cleMaitre => _cleMaitre;

  void _changer(EtatSession e) {
    _etat = e;
    notifyListeners();
  }

  /// Au lancement : reprend la session enregistrée, ou passe en mode visiteur.
  Future<void> demarrer() async {
    final jeton = await coffre.jeton;
    if (jeton == null) {
      _changer(const EtatSession(ModeSession.visiteur));
      return;
    }
    api.jeton = jeton;
    _cleMaitre = await coffre.cleMaitre;
    final compteLocal = await base.lireMeta<Map<String, Object?>>('compte');
    // Hors ligne : on garde la session locale ; le serveur sera interrogé plus tard.
    _changer(EtatSession(_cleMaitre != null ? ModeSession.actif : ModeSession.enAttente, compte: compteLocal));
    try {
      await rafraichirCompte();
    } on ErreurApi catch (e) {
      if (!e.horsLigne) rethrow;
    }
  }

  Future<void> rafraichirCompte() async {
    final compte = await api.get('/compte') as Map<String, dynamic>;
    await base.ecrireMeta('compte', compte);
    _changer(EtatSession(_etat.mode, compte: compte, appareil: _etat.appareil));
  }

  // --- Inscription (A1) ------------------------------------------------------------------

  Future<List<dynamic>> conditionsActuelles() async => await api.get('/conditions/actuelles') as List<dynamic>;

  Future<void> inscrire(String email, String nom, String motDePasse, List<String> conditions) async {
    await api.post('/auth/inscription', {
      'email': email,
      'nomAffichage': nom,
      'motDePasse': motDePasse,
      'conditionsAcceptees': conditions,
    });
  }

  Future<void> renvoyerCode(String email) => api.post('/auth/renvoyer-code', {'email': email, 'type': 'INSCRIPTION'});

  Future<Map<String, dynamic>> _nouvelAppareil(String nom, String type, String plateforme) async {
    final paire = crypto.paireAppareil();
    await coffre.ecrirePaireAppareil(paire.publique, paire.privee);
    return {
      'nom': nom,
      'type': type,
      'plateforme': plateforme,
      'versionApp': Config.versionApp,
      'clePublique': encoderB64(paire.publique),
    };
  }

  /// Vérifie le code, crée la clé maître et la clé de récupération (ADR-004).
  Future<InscriptionTerminee> verifierInscription(
      String email, String code, ({String nom, String type, String plateforme}) appareil,
      {bool conserverDonneesLocales = true}) async {
    final maitre = crypto.aleatoire(32);
    final recup = crypto.aleatoire(32);
    final descr = await _nouvelAppareil(appareil.nom, appareil.type, appareil.plateforme);
    final paire = (await coffre.paireAppareil)!;
    final reponse = await api.post('/auth/inscription/verifier', {
      'email': email,
      'code': code,
      'appareil': descr,
      'cles': {
        'enveloppeRecuperation': encoderB64(crypto.enveloppeRecuperation(recup, maitre)),
        'enveloppeAppareil': encoderB64(crypto.scellerPour(paire.publique, maitre)),
        'clePubliqueVerification': encoderB64(crypto.clePubliqueVerification(maitre)),
      },
    }) as Map<String, dynamic>;
    await _ouvrirSession(reponse, maitre);
    if (conserverDonneesLocales) {
      await base.toutMarquerAEnvoyer(); // I3 : les données du visiteur rejoignent le compte
    } else {
      await base.toutEffacer();
    }
    return InscriptionTerminee(Base32Crockford.encoder(recup));
  }

  Future<void> confirmerCleRecuperation() async {
    await api.post('/compte/cle-recuperation/confirmer');
    await rafraichirCompte();
  }

  // --- Connexion (A2) ----------------------------------------------------------------------

  Future<void> connecter(String email, String motDePasse, ({String nom, String type, String plateforme}) appareil) async {
    final connu = await coffre.appareilId;
    final paire = await coffre.paireAppareil;
    final descr = connu != null && paire != null
        ? {'appareilId': connu}
        : await _nouvelAppareil(appareil.nom, appareil.type, appareil.plateforme);
    Map<String, dynamic> reponse;
    try {
      reponse = await api.post('/auth/connexion', {'email': email, 'motDePasse': motDePasse, 'appareil': descr})
          as Map<String, dynamic>;
    } on ErreurApi catch (e) {
      // Appareil révoqué ou inconnu côté serveur : on se présente comme un nouvel appareil.
      if (!descr.containsKey('appareilId') || (e.code != 'appareil_revoque' && e.code != 'introuvable')) rethrow;
      await coffre.toutEffacer();
      final nouveau = await _nouvelAppareil(appareil.nom, appareil.type, appareil.plateforme);
      reponse = await api.post('/auth/connexion', {'email': email, 'motDePasse': motDePasse, 'appareil': nouveau})
          as Map<String, dynamic>;
    }
    await _ouvrirSession(reponse, await coffre.cleMaitre);
  }

  Future<void> _ouvrirSession(Map<String, dynamic> reponse, Uint8List? maitre) async {
    final jeton = (reponse['session'] as Map<String, dynamic>)['jeton'] as String;
    final appareil = reponse['appareil'] as Map<String, dynamic>;
    api.jeton = jeton;
    await coffre.ecrireJeton(jeton);
    await coffre.ecrireAppareilId(appareil['id'] as String);
    await base.ecrireMeta('compte', reponse['compte']);
    if (appareil['statut'] == 'ACTIF') {
      maitre ??= await _recupererMaitreDepuisEnveloppe();
      await _activer(maitre);
      _changer(EtatSession(ModeSession.actif, compte: reponse['compte'] as Map<String, dynamic>, appareil: appareil));
    } else {
      _changer(EtatSession(ModeSession.enAttente, compte: reponse['compte'] as Map<String, dynamic>, appareil: appareil));
    }
  }

  Future<Uint8List> _recupererMaitreDepuisEnveloppe() async {
    final paire = (await coffre.paireAppareil)!;
    final r = await api.get('/appareils/courant/enveloppe') as Map<String, dynamic>;
    return crypto.desceller(decoderB64(r['cleMaitreEnveloppee'] as String), paire.publique, paire.privee);
  }

  Future<void> _activer(Uint8List maitre) async {
    _cleMaitre = maitre;
    await coffre.ecrireCleMaitre(maitre);
  }

  // --- Déverrouillage d'un nouvel appareil (I11) ------------------------------------------

  /// Crée la demande et renvoie le code à afficher ; attend ensuite l'approbation.
  Future<Map<String, dynamic>> demanderDeverrouillage() async =>
      await api.post('/appareils/courant/deverrouillage') as Map<String, dynamic>;

  /// Interroge le serveur jusqu'à l'approbation (l'enveloppe devient lisible).
  Future<bool> verifierDeverrouillage() async {
    try {
      final maitre = await _recupererMaitreDepuisEnveloppe();
      await _activer(maitre);
      _changer(EtatSession(ModeSession.actif, compte: _etat.compte));
      await rafraichirCompte();
      return true;
    } on ErreurApi catch (e) {
      if (e.code == 'appareil_non_deverrouille' || e.horsLigne) return false;
      rethrow;
    }
  }

  Future<void> deverrouillerParRecuperation(String cleSaisie) async {
    final recup = Base32Crockford.decoder(cleSaisie);
    final r = await api.get('/compte/enveloppe-recuperation') as Map<String, dynamic>;
    final Uint8List maitre;
    try {
      maitre = crypto.ouvrirRecuperation(recup, decoderB64(r['cleMaitreEnveloppee'] as String));
    } catch (_) {
      throw ErreurApi(422, 'cle_recuperation_incorrecte', 'Clé de récupération incorrecte.');
    }
    final paire = (await coffre.paireAppareil)!;
    await api.post('/appareils/courant/deverrouiller-par-recuperation', {
      'cleMaitreEnveloppee': encoderB64(crypto.scellerPour(paire.publique, maitre)),
      'signatureDefi': encoderB64(crypto.signerDefi(maitre, decoderB64(r['defi'] as String))),
    });
    await _activer(maitre);
    _changer(EtatSession(ModeSession.actif, compte: _etat.compte));
    await rafraichirCompte();
  }

  /// Sur un appareil actif : approuve la demande d'un nouvel appareil (le code est recopié par l'utilisateur).
  Future<void> approuver(Map<String, dynamic> demande, String code) async {
    final maitre = _cleMaitre!;
    final enveloppe = crypto.scellerPour(decoderB64(demande['clePubliqueDemandeur'] as String), maitre);
    await api.post('/deverrouillages/${demande['id']}/approuver', {
      'codeAffiche': code,
      'cleMaitreEnveloppee': encoderB64(enveloppe),
    });
  }

  Future<void> refuser(String demandeId) => api.post('/deverrouillages/$demandeId/refuser');

  Future<String> regenererCleRecuperation(String motDePasse) async {
    final recup = crypto.aleatoire(32);
    await api.put('/compte/enveloppe-recuperation', {
      'motDePasse': motDePasse,
      'cleMaitreEnveloppee': encoderB64(crypto.enveloppeRecuperation(recup, _cleMaitre!)),
    });
    await rafraichirCompte();
    return Base32Crockford.encoder(recup);
  }

  // --- Sortie ------------------------------------------------------------------------------

  /// Déconnexion : clés et données locales effacées de cet appareil (D43).
  Future<void> deconnecter() async {
    try {
      await api.post('/auth/deconnexion');
    } catch (_) {}
    await _effacerTout();
  }

  Future<void> _sessionPerdue() async {
    if (_etat.connecte) await _effacerTout();
  }

  Future<void> appareilRevoque() => _effacerTout();

  Future<void> _effacerTout() async {
    api.jeton = null;
    _cleMaitre = null;
    await coffre.toutEffacer();
    await base.toutEffacer();
    _changer(const EtatSession(ModeSession.visiteur));
  }
}
