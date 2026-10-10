"""Protocole de synchronisation (contrat 2.5, ADR-005).

- Chaque changement accepté reçoit la version suivante du compteur du compte.
- « La dernière modification gagne » (horodatage client `modifieLe`).
- Une suppression est définitive : un élément supprimé ne revient jamais (décision D19).
- Le serveur archive lui-même les anciennes versions de post-it (C3, décision D20).
"""

import logging
import uuid
from dataclasses import dataclass

from django.db import transaction
from django.utils import timezone
from rest_framework import serializers

from apps.elements.models import (
    CompteurSynchro,
    Element,
    ElementEtiquette,
    Etiquette,
    JourSemaine,
    Rappel,
    Recurrence,
    Tableau,
    TypeContenuPP,
    TypeElement,
    VersionPostIt,
)
from commun.b64 import ChampBase64Url, encoder
from commun.evenements import publier

journal = logging.getLogger(__name__)

SURCOUT_CHIFFREMENT = 1024  # nonce + tag + en-tête de format, large
TAILLE_MAX_ELEMENT = 10 * 1024 * 1024 + SURCOUT_CHIFFREMENT  # 10 Mo chiffrés (validé le 09/10)
TAILLE_MAX_PP = {
    TypeContenuPP.TEXTE: 100 * 1024 + SURCOUT_CHIFFREMENT,  # B1
    TypeContenuPP.LIEN: 100 * 1024 + SURCOUT_CHIFFREMENT,
    TypeContenuPP.IMAGE: 5 * 1024 * 1024 + SURCOUT_CHIFFREMENT,
}
LIMITE_LOT = 500

# Crochets appelés après la suppression d'un élément (fichiers, liens publics).
_apres_suppression = []


def apres_suppression_element(fonction):
    _apres_suppression.append(fonction)
    return fonction


# --- Validation des données de chaque entité ----------------------------------------------


def _contenu(**kw):
    return ChampBase64Url(taille_min=1, taille_max=TAILLE_MAX_ELEMENT, required=False, allow_null=True, **kw)


class DonneesElement(serializers.Serializer):
    type = serializers.ChoiceField(choices=TypeElement.choices)
    parentId = serializers.UUIDField(required=False, allow_null=True)
    elementSourceId = serializers.UUIDField(required=False, allow_null=True)
    epingleAccesRapide = serializers.BooleanField(default=False)
    epingle = serializers.BooleanField(default=False)
    typeContenu = serializers.ChoiceField(choices=TypeContenuPP.choices, required=False, allow_null=True)
    archive = serializers.BooleanField(default=False)
    cleElementEnveloppee = ChampBase64Url(taille_min=32, taille_max=512, required=False, allow_null=True)
    contenuChiffre = _contenu()

    def validate(self, d):
        if d["type"] == TypeElement.PRESSE_PAPIER:
            if not d.get("typeContenu"):
                raise serializers.ValidationError({"typeContenu": "requis"}, code="requis")
            contenu = d.get("contenuChiffre")
            if contenu is not None and len(contenu) > TAILLE_MAX_PP[d["typeContenu"]]:
                raise serializers.ValidationError({"contenuChiffre": "trop volumineux"}, code="trop_volumineux")
        return d


class DonneesSimples(serializers.Serializer):
    contenuChiffre = _contenu()


class DonneesLiaison(serializers.Serializer):
    elementId = serializers.UUIDField()
    etiquetteId = serializers.UUIDField()


class DonneesRappel(serializers.Serializer):
    elementId = serializers.UUIDField()
    prochaineEcheance = serializers.DateTimeField()
    recurrence = serializers.ChoiceField(choices=Recurrence.choices, required=False, allow_null=True)
    joursSemaine = serializers.ListField(child=serializers.ChoiceField(choices=JourSemaine.choices), max_length=7, default=list)
    fuseauHoraire = serializers.CharField(max_length=64, default="UTC")
    actif = serializers.BooleanField(default=True)

    def validate_fuseauHoraire(self, valeur):
        from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

        try:
            ZoneInfo(valeur)
        except (ZoneInfoNotFoundError, ValueError):
            raise serializers.ValidationError("Fuseau horaire inconnu.", code="invalide")
        return valeur


@dataclass(frozen=True)
class Definition:
    modele: type
    donnees: type | None  # None = entité en lecture seule pour le client


ENTITES = {
    "element": Definition(Element, DonneesElement),
    "tableau": Definition(Tableau, DonneesSimples),
    "etiquette": Definition(Etiquette, DonneesSimples),
    "element_etiquette": Definition(ElementEtiquette, DonneesLiaison),
    "rappel": Definition(Rappel, DonneesRappel),
    "version_post_it": Definition(VersionPostIt, None),
}


class ChangementSerializer(serializers.Serializer):
    entite = serializers.ChoiceField(choices=list(ENTITES))
    id = serializers.UUIDField()
    modifieLe = serializers.DateTimeField()
    supprimeLe = serializers.DateTimeField(required=False, allow_null=True)
    donnees = serializers.DictField(required=False, default=dict)


# --- Représentation (pull) ----------------------------------------------------------------


def _b64(valeur):
    return encoder(bytes(valeur)) if valeur else None


def _donnees(entite, objet):
    if entite == "element":
        return {
            "type": objet.type,
            "parentId": objet.parent_id,
            "elementSourceId": objet.element_source_id,
            "epingleAccesRapide": objet.epingle_acces_rapide,
            "epingle": objet.epingle,
            "typeContenu": objet.type_contenu,
            "archive": objet.archive,
            "appareilAuteurId": objet.appareil_auteur_id,
            "cleElementEnveloppee": _b64(objet.cle_element_enveloppee),
            "contenuChiffre": _b64(objet.contenu_chiffre),
        }
    if entite in ("tableau", "etiquette"):
        return {"contenuChiffre": _b64(objet.contenu_chiffre)}
    if entite == "element_etiquette":
        return {"elementId": objet.element_id, "etiquetteId": objet.etiquette_id}
    if entite == "rappel":
        return {
            "elementId": objet.element_id,
            "prochaineEcheance": objet.prochaine_echeance,
            "recurrence": objet.recurrence,
            "joursSemaine": objet.jours_semaine,
            "fuseauHoraire": objet.fuseau_horaire,
            "actif": objet.actif,
        }
    return {
        "postItId": objet.post_it_id,
        "appareilAuteurId": objet.appareil_auteur_id,
        "contenuChiffre": _b64(objet.contenu_chiffre),
        "creeLe": objet.cree_le,
    }


def representer(entite, objet):
    return {
        "entite": entite,
        "id": objet.id,
        "version": objet.version,
        "modifieLe": objet.modifie_le,
        "supprimeLe": objet.supprime_le,
        "donnees": _donnees(entite, objet),
    }


def changements_depuis(compte, depuis, limite):
    """Pull incrémental : tous les changements de version > depuis, toutes entités confondues, triés."""
    limite = max(1, min(limite, LIMITE_LOT))
    candidats = []
    for entite, definition in ENTITES.items():
        for objet in definition.modele.objects.filter(compte=compte, version__gt=depuis).order_by("version")[: limite + 1]:
            candidats.append((objet.version, entite, objet))
    candidats.sort(key=lambda c: c[0])
    encore = len(candidats) > limite
    retenus = candidats[:limite]
    if encore:
        version_courante = retenus[-1][0]
    else:
        compteur = CompteurSynchro.objects.filter(compte=compte).first()
        version_courante = compteur.version if compteur else 0
    return version_courante, [representer(e, o) for _, e, o in retenus], encore


# --- Application des changements (push) ---------------------------------------------------


def _resultat(entite, id_, statut, version=None, code=None):
    r = {"entite": entite, "id": str(id_), "statut": statut}
    if version is not None:
        r["versionServeur"] = version
    if code:
        r["code"] = code
    return r


class _Compteur:
    def __init__(self, compte):
        self.ligne, _ = CompteurSynchro.objects.get_or_create(compte=compte)
        self.ligne = CompteurSynchro.objects.select_for_update().get(pk=self.ligne.pk)

    def suivante(self):
        self.ligne.version += 1
        return self.ligne.version

    def enregistrer(self):
        self.ligne.save(update_fields=["version"])


def _appliquer_donnees(entite, objet, d):
    if entite == "element":
        objet.type = d["type"]
        objet.parent_id = d.get("parentId")
        objet.element_source_id = d.get("elementSourceId")
        objet.epingle_acces_rapide = d["epingleAccesRapide"]
        objet.epingle = d["epingle"]
        objet.type_contenu = d.get("typeContenu")
        objet.archive = d["archive"]
        if "cleElementEnveloppee" in d:
            objet.cle_element_enveloppee = d["cleElementEnveloppee"]
        if "contenuChiffre" in d:
            objet.contenu_chiffre = d["contenuChiffre"]
    elif entite in ("tableau", "etiquette"):
        if "contenuChiffre" in d:
            objet.contenu_chiffre = d["contenuChiffre"]
    elif entite == "element_etiquette":
        objet.element_id = d["elementId"]
        objet.etiquette_id = d["etiquetteId"]
    elif entite == "rappel":
        objet.element_id = d["elementId"]
        objet.prochaine_echeance = d["prochaineEcheance"]
        objet.recurrence = d.get("recurrence")
        objet.jours_semaine = d["joursSemaine"]
        objet.fuseau_horaire = d["fuseauHoraire"]
        objet.actif = d["actif"]


def _effacer_contenu(entite, objet):
    """Suppression : le serveur ne garde qu'un marqueur, sans aucun contenu."""
    if hasattr(objet, "contenu_chiffre"):
        objet.contenu_chiffre = None
    if entite == "element":
        objet.cle_element_enveloppee = None


def _archiver_version(compte, compteur, post_it, contenu, auteur, date):
    if not contenu:
        return
    VersionPostIt.objects.create(
        id=uuid.uuid4(),
        compte=compte,
        version=compteur.suivante(),
        modifie_le=date,
        post_it_id=post_it.id,
        appareil_auteur=auteur,
        contenu_chiffre=contenu,
        cree_le=date,
    )


def _appliquer(compte, appareil, compteur, ch, apres_commit):
    entite, id_ = ch["entite"], ch["id"]
    definition = ENTITES[entite]
    if definition.donnees is None:
        return _resultat(entite, id_, "rejete", code="lecture_seule")

    supprime_le = ch.get("supprimeLe")
    d = {}
    if not supprime_le:
        validateur = definition.donnees(data=ch["donnees"])
        if not validateur.is_valid():
            return _resultat(entite, id_, "rejete", code="validation")
        d = validateur.validated_data

    modele = definition.modele
    existant = modele.objects.select_for_update().filter(id=id_).first()
    if existant is not None and existant.compte_id != compte.id:
        return _resultat(entite, id_, "rejete", code="introuvable")  # ne révèle pas l'existence

    if existant is None:
        if supprime_le:
            return _resultat(entite, id_, "accepte")  # rien à supprimer
        if entite == "element" and d["type"] == TypeElement.FICHIER:
            return _resultat(entite, id_, "rejete", code="reserve_aux_fichiers")  # créé par POST /fichiers
        objet = modele(id=id_, compte=compte, modifie_le=ch["modifieLe"])
        if entite == "element":
            objet.appareil_auteur = appareil
        _appliquer_donnees(entite, objet, d)
        objet.version = compteur.suivante()
        objet.save(force_insert=True)
        return _resultat(entite, id_, "accepte", objet.version)

    # Suppression définitive (D19).
    if existant.supprime_le is not None:
        return _resultat(entite, id_, "accepte" if supprime_le else "ecrase_par_plus_recent", existant.version)

    if ch["modifieLe"] < existant.modifie_le:
        if entite == "element" and existant.type == TypeElement.POST_IT and d.get("contenuChiffre"):
            # Le perdant du conflit est conservé dans l'historique (C3, I6).
            _archiver_version(compte, compteur, existant, d["contenuChiffre"], appareil, ch["modifieLe"])
            apres_commit.append(lambda: publier(compte.id, "conflit", entite=entite, id=id_))
        return _resultat(entite, id_, "ecrase_par_plus_recent", existant.version)

    if entite == "element" and not supprime_le and d["type"] != existant.type:
        return _resultat(entite, id_, "rejete", code="type_immuable")

    if supprime_le:
        existant.supprime_le = supprime_le
        _effacer_contenu(entite, existant)
        if entite == "element":
            for crochet in _apres_suppression:
                crochet(existant)
    else:
        if (
            entite == "element"
            and existant.type == TypeElement.POST_IT
            and "contenuChiffre" in d
            and existant.contenu_chiffre
            and bytes(existant.contenu_chiffre) != (d["contenuChiffre"] or b"")
        ):
            _archiver_version(
                compte, compteur, existant, bytes(existant.contenu_chiffre), existant.appareil_auteur, existant.modifie_le
            )
        _appliquer_donnees(entite, existant, d)
        if entite == "element":
            existant.appareil_auteur = appareil
    existant.modifie_le = ch["modifieLe"]
    existant.version = compteur.suivante()
    existant.save()
    return _resultat(entite, id_, "accepte", existant.version)


def appliquer_changements(compte, appareil, changements):
    apres_commit = []
    with transaction.atomic():
        compteur = _Compteur(compte)
        depart = compteur.ligne.version
        resultats = [_appliquer(compte, appareil, compteur, ch, apres_commit) for ch in changements]
        compteur.enregistrer()
        version = compteur.ligne.version
        if version != depart:
            publier(compte.id, "changements", versionCourante=version)
        for action in apres_commit:
            action()
    return version, resultats
