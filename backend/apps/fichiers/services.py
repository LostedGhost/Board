"""Contrat 2.7 — fichiers chiffrés (E1, E2)."""

import os
import re
import tempfile
import uuid
from pathlib import Path

from django.conf import settings
from django.db import transaction
from rest_framework import status

from apps.elements.models import Element, TypeElement
from apps.fichiers import stockage
from apps.fichiers.models import Fichier, FournisseurStockage, StatutFichier
from apps.synchro.services import _Compteur, apres_suppression_element
from commun.erreurs import ErreurApi
from commun.evenements import publier

TAILLE_MAX_FICHIER = 100 * 1024 * 1024 + stockage.TAILLE_MORCEAU // 1024  # 100 Mo + surcoût du chiffrement par blocs


def dossier_temporaire():
    dossier = Path(getattr(settings, "FICHIERS_DOSSIER_TEMPORAIRE", "") or Path(tempfile.gettempdir()) / "luluboard")
    dossier.mkdir(parents=True, exist_ok=True)
    return dossier


def _introuvable():
    return ErreurApi("introuvable", "Ressource introuvable.", status.HTTP_404_NOT_FOUND)


def fichier_du_compte(compte, fichier_id):
    fichier = (
        Fichier.objects.select_related("element")
        .filter(element_id=fichier_id, element__compte=compte, element__supprime_le__isnull=True)
        .first()
    )
    if fichier is None:
        raise _introuvable()
    return fichier


def creer(compte, appareil, meta, televerse):
    """Enregistre le fichier chiffré en local, crée l'élément FICHIER, puis lance le transfert en tâche de fond."""
    if televerse.size > TAILLE_MAX_FICHIER:
        raise ErreurApi("fichier_trop_volumineux", "Fichier trop volumineux (100 Mo maximum).", status.HTTP_413_REQUEST_ENTITY_TOO_LARGE)
    if televerse.size != meta["tailleOctets"]:
        raise ErreurApi("validation", "Taille annoncée incorrecte.", status.HTTP_422_UNPROCESSABLE_ENTITY,
                        champs=[{"champ": "tailleOctets", "raison": "incoherente"}])
    if Element.objects.filter(id=meta["id"]).exists():
        raise ErreurApi("deja_traite", "Cet identifiant existe déjà.", status.HTTP_409_CONFLICT)

    chemin = dossier_temporaire() / f"{uuid.uuid4().hex}.bin"
    with open(chemin, "wb") as sortie:
        for bloc in televerse.chunks():
            sortie.write(bloc)

    try:
        with transaction.atomic():
            compteur = _Compteur(compte)
            element = Element.objects.create(
                id=meta["id"],
                compte=compte,
                type=TypeElement.FICHIER,
                version=compteur.suivante(),
                modifie_le=meta["modifieLe"],
                appareil_auteur=appareil,
                cle_element_enveloppee=meta["cleElementEnveloppee"],
                contenu_chiffre=meta["contenuChiffre"],
            )
            compteur.enregistrer()
            fichier = Fichier.objects.create(
                element=element,
                taille_octets=televerse.size,
                fournisseur=stockage.fournisseur_actif(),
                chemin_temporaire=str(chemin),
            )
            publier(compte.id, "changements", versionCourante=element.version)
            from apps.fichiers.taches import transferer

            transaction.on_commit(lambda: transferer.delay(str(element.id)))
    except Exception:
        os.unlink(chemin)
        raise
    return fichier


def reessayer(fichier):
    if fichier.statut != StatutFichier.ECHEC:
        raise ErreurApi("deja_traite", "Ce fichier n'est pas en échec.", status.HTTP_409_CONFLICT)
    if not fichier.chemin_temporaire or not os.path.exists(fichier.chemin_temporaire):
        raise ErreurApi("code_expire", "La copie temporaire a expiré : envoyez le fichier à nouveau.", status.HTTP_410_GONE)
    fichier.statut = StatutFichier.EN_FILE
    fichier.message_erreur = None
    fichier.save(update_fields=["statut", "message_erreur"])
    from apps.fichiers.taches import transferer

    transaction.on_commit(lambda: transferer.delay(str(fichier.element_id)))
    return fichier


def acces(fichier):
    if fichier.statut != StatutFichier.PRET:
        raise ErreurApi("deja_traite", "Le fichier n'est pas encore prêt.", status.HTTP_409_CONFLICT)
    if fichier.fournisseur == FournisseurStockage.LULUFILES and settings.LULUFILES_CORS_OUVERT:
        url, expire = stockage.LuluFiles().lien_signe(fichier.id_lulufiles)
        return {"mode": "lien_signe", "url": url, "expireLe": expire}
    return {"mode": "flux", "url": f"/api/v1/fichiers/{fichier.element_id}/contenu"}


# --- Lecture en flux, avec Range ----------------------------------------------------------

_PLAGE = re.compile(r"^bytes=(\d*)-(\d*)$")


def analyser_plage(entete, taille):
    """Renvoie (debut, fin incluse) ou None (fichier entier). Lève 416 si la plage est hors du fichier."""
    if not entete:
        return None
    trouve = _PLAGE.match(entete.strip())
    if not trouve or (not trouve.group(1) and not trouve.group(2)):
        return None
    if trouve.group(1):
        debut = int(trouve.group(1))
        fin = int(trouve.group(2)) if trouve.group(2) else taille - 1
    else:  # suffixe : les N derniers octets
        debut = max(0, taille - int(trouve.group(2)))
        fin = taille - 1
    fin = min(fin, taille - 1)
    if debut > fin or debut >= taille:
        raise ErreurApi("requete_invalide", "Plage hors du fichier.", status.HTTP_416_REQUESTED_RANGE_NOT_SATISFIABLE)
    return debut, fin


def flux_telegram(fichier, debut, fin):
    """Morceau par morceau : chaque morceau est vérifié (SHA-256) avant d'être envoyé."""
    telegram = stockage.Telegram()
    position = 0
    for morceau in fichier.morceaux.all():
        m_debut, m_fin = position, position + morceau.taille_octets - 1
        position += morceau.taille_octets
        if m_fin < debut or m_debut > fin:
            continue
        octets = telegram.lire_morceau(morceau.file_id_telegram)
        if stockage.sha256(octets) != morceau.sha256:
            raise stockage.ErreurStockage("Morceau corrompu détecté.", reessayable=False)
        yield octets[max(0, debut - m_debut): min(len(octets), fin - m_debut + 1)]


@apres_suppression_element
def _apres_suppression(element):
    """Suppression définitive (pas de corbeille) : effacement chez le fournisseur après validation."""
    if element.type != TypeElement.FICHIER:
        return
    fichier = Fichier.objects.filter(element=element).first()
    if fichier is None:
        return
    from apps.fichiers.taches import effacer_du_stockage

    infos = {
        "fournisseur": fichier.fournisseur,
        "id_lulufiles": str(fichier.id_lulufiles) if fichier.id_lulufiles else None,
        "messages": list(fichier.morceaux.values_list("message_id", flat=True)),
        "chemin": fichier.chemin_temporaire,
    }
    transaction.on_commit(lambda: effacer_du_stockage.delay(infos))
