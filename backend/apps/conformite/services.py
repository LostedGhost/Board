"""Conditions d'utilisation en vigueur et acceptations (G4, I23)."""

from django.db.models import Max
from django.utils import timezone

from apps.conformite.models import AcceptationConditions, VersionConditions


def conditions_actuelles():
    """La version publiée la plus récente de chaque type de conditions."""
    maintenant = timezone.now()
    publiees = VersionConditions.objects.filter(publiee_le__lte=maintenant)
    dernieres = publiees.values("type").annotate(derniere=Max("publiee_le"))
    filtre = [(d["type"], d["derniere"]) for d in dernieres]
    resultat = []
    for type_, date in filtre:
        version = publiees.filter(type=type_, publiee_le=date).order_by("-numero").first()
        if version:
            resultat.append(version)
    return resultat


def conditions_a_accepter(compte):
    acceptees = set(AcceptationConditions.objects.filter(compte=compte).values_list("version_id", flat=True))
    return [v for v in conditions_actuelles() if v.id not in acceptees]


def ids_manquants(version_ids):
    """Versions actuelles absentes de la liste fournie par le client."""
    fournies = {str(v) for v in version_ids}
    return [str(v.id) for v in conditions_actuelles() if str(v.id) not in fournies]


def enregistrer_acceptations(compte, version_ids):
    actuelles = {str(v.id): v for v in conditions_actuelles()}
    for vid in version_ids:
        version = actuelles.get(str(vid))
        if version:
            AcceptationConditions.objects.get_or_create(compte=compte, version=version)
