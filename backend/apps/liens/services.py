"""Contrats 2.9 et 2.10 — liens publics en direct (E3, H4, I19, I21)."""

import hashlib
import hmac
import secrets
from datetime import timedelta

from django.conf import settings
from django.core import signing
from django.db.models import F
from django.utils import timezone
from rest_framework import status

from apps.comptes.models import DureeConservation
from apps.elements.models import Element, TypeElement
from apps.liens.models import LienPublic
from apps.synchro.services import apres_suppression_element
from commun import limitation
from commun.erreurs import ErreurApi

TYPES_PARTAGEABLES = {TypeElement.POST_IT, TypeElement.SNIPPET, TypeElement.LISTE_TACHES, TypeElement.FICHIER}  # H4
DUREES = {
    DureeConservation.J90: timedelta(days=90),
    DureeConservation.J30: timedelta(days=30),
    DureeConservation.J7: timedelta(days=7),
    DureeConservation.H24: timedelta(hours=24),
    DureeConservation.H1: timedelta(hours=1),
    DureeConservation.MIN30: timedelta(minutes=30),
}
ESSAIS_MAX = 5  # I19
FENETRE_S = 15 * 60
DUREE_JETON_TELECHARGEMENT_S = 600
PROFONDEUR_MAX = 50


def hacher(valeur):
    return hashlib.sha256(valeur.encode("ascii")).hexdigest()


def hmac_verificateur(octets):
    return hmac.new(settings.SECRET_KEY.encode(), octets, hashlib.sha256).hexdigest()


def expiration(duree, depuis=None):
    if duree == DureeConservation.INFINIE:
        return None
    return (depuis or timezone.now()) + DUREES[duree]


def statut(lien):
    if lien.desactive_par_admin_le:
        return "DESACTIVE"
    if lien.revoque_le or lien.element.supprime_le:
        return "REVOQUE"
    if lien.expire_le and lien.expire_le <= timezone.now():
        return "EXPIRE"
    return "ACTIF"


def creer(compte, d):
    element = Element.objects.filter(id=d["elementId"], compte=compte, supprime_le__isnull=True).first()
    if element is None:
        raise ErreurApi("introuvable", "Élément introuvable.", status.HTTP_404_NOT_FOUND)
    if element.type not in TYPES_PARTAGEABLES:
        raise ErreurApi("validation", "Ce type d'élément ne se partage pas par lien.", status.HTTP_422_UNPROCESSABLE_ENTITY,
                        champs=[{"champ": "elementId", "raison": "type_non_partageable"}])
    if element.type == TypeElement.FICHIER and getattr(getattr(element, "fichier", None), "statut", None) != "PRET":
        raise ErreurApi("deja_traite", "Le fichier n'est pas encore prêt.", status.HTTP_409_CONFLICT)
    protege = d["protegeParMotDePasse"]
    champs_mdp = ("selDerivation", "cleElementEnveloppee", "verificateurMotDePasse")
    if protege and not all(d.get(c) for c in champs_mdp):
        raise ErreurApi("validation", "Lien protégé : sel, clé enveloppée et vérificateur requis.", status.HTTP_422_UNPROCESSABLE_ENTITY)
    if not protege and any(d.get(c) for c in champs_mdp):
        raise ErreurApi("validation", "Lien sans mot de passe : aucune donnée de mot de passe attendue.", status.HTTP_422_UNPROCESSABLE_ENTITY)

    jeton = secrets.token_urlsafe(24)
    lien = LienPublic.objects.create(
        compte=compte,
        element=element,
        jeton_hash=hacher(jeton),
        protege_par_mot_de_passe=protege,
        sel_derivation=d.get("selDerivation"),
        cle_element_enveloppee=d.get("cleElementEnveloppee"),
        verificateur_mot_de_passe_hash=hmac_verificateur(d["verificateurMotDePasse"]) if protege else None,
        duree=d["duree"],
        expire_le=expiration(d["duree"]),
    )
    return lien, jeton


@apres_suppression_element
def _revoquer_liens(element):
    LienPublic.objects.filter(element=element, revoque_le__isnull=True).update(revoque_le=timezone.now())


# --- Consultation publique ----------------------------------------------------------------


def lien_actif(jeton):
    lien = LienPublic.objects.select_related("element").filter(jeton_hash=hacher(jeton)).first()
    if lien is None or statut(lien) != "ACTIF":
        # Même réponse dans tous les cas : on ne dit pas si le lien a existé (I19).
        raise ErreurApi("lien_expire", "Ce lien n'est plus disponible.", status.HTTP_410_GONE)
    return lien


def taches_de_la_liste(liste):
    """Toutes les tâches et sous-tâches d'une liste, quelle que soit la profondeur (H4 en direct)."""
    resultat, parents = [], [liste.id]
    for _ in range(PROFONDEUR_MAX):
        enfants = list(
            Element.objects.filter(compte=liste.compte, type=TypeElement.TACHE, parent_id__in=parents, supprime_le__isnull=True)
        )
        if not enfants:
            break
        resultat.extend(enfants)
        parents = [e.id for e in enfants]
    return resultat


def verifier_mot_de_passe(lien, verificateur, ip):
    cle = f"{lien.id}:{ip}"
    if limitation.valeur("lien_essais", cle) >= ESSAIS_MAX:
        raise ErreurApi("lien_bloque", "Trop d'essais. Réessayez dans 15 minutes.", status.HTTP_423_LOCKED)
    if not hmac.compare_digest(lien.verificateur_mot_de_passe_hash or "", hmac_verificateur(verificateur)):
        limitation.compter("lien_essais", cle, FENETRE_S)
        raise ErreurApi("validation", "Mot de passe incorrect.", status.HTTP_422_UNPROCESSABLE_ENTITY,
                        champs=[{"champ": "verificateurMotDePasse", "raison": "incorrect"}])
    limitation.reinitialiser("lien_essais", cle)


def jeton_telechargement(lien):
    return signing.dumps({"lien": str(lien.id)}, salt="lien-telechargement")


def verifier_jeton_telechargement(lien, jeton):
    try:
        donnees = signing.loads(jeton or "", salt="lien-telechargement", max_age=DUREE_JETON_TELECHARGEMENT_S)
    except signing.BadSignature:
        raise ErreurApi("interdit", "Déverrouillez d'abord le lien.", status.HTTP_403_FORBIDDEN)
    if donnees.get("lien") != str(lien.id):
        raise ErreurApi("interdit", "Déverrouillez d'abord le lien.", status.HTTP_403_FORBIDDEN)


def compter_telechargement(lien):
    LienPublic.objects.filter(pk=lien.pk).update(nb_telechargements=F("nb_telechargements") + 1)
