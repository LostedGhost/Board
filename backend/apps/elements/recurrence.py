"""Calcul de la prochaine échéance d'un rappel récurrent (F3), dans le fuseau horaire du rappel."""

import calendar
from datetime import timedelta
from zoneinfo import ZoneInfo

JOURS = ["LUNDI", "MARDI", "MERCREDI", "JEUDI", "VENDREDI", "SAMEDI", "DIMANCHE"]


def _ajouter_mois(local, mois):
    annee = local.year + (local.month - 1 + mois) // 12
    m = (local.month - 1 + mois) % 12 + 1
    jour = min(local.day, calendar.monthrange(annee, m)[1])  # 31 → dernier jour du mois
    return local.replace(year=annee, month=m, day=jour)


def suivante(echeance, recurrence, jours_semaine, fuseau):
    """Occurrence qui suit `echeance` (même heure locale, changements d'heure compris)."""
    zone = ZoneInfo(fuseau or "UTC")
    local = echeance.astimezone(zone).replace(tzinfo=None)
    if recurrence == "QUOTIDIENNE":
        local = local + timedelta(days=1)
    elif recurrence == "HEBDOMADAIRE":
        jours = sorted(JOURS.index(j) for j in (jours_semaine or []))
        if not jours:
            local = local + timedelta(days=7)
        else:
            for ecart in range(1, 8):
                if (local.weekday() + ecart) % 7 in jours:
                    local = local + timedelta(days=ecart)
                    break
    elif recurrence == "MENSUELLE":
        local = _ajouter_mois(local, 1)
    elif recurrence == "ANNUELLE":
        local = _ajouter_mois(local, 12)
    else:
        return None
    return local.replace(tzinfo=zone)


def prochaine_apres(echeance, recurrence, jours_semaine, fuseau, maintenant):
    """Saute les occurrences déjà passées (une seule notification pour un rattrapage)."""
    prochaine = echeance
    for _ in range(1000):
        prochaine = suivante(prochaine, recurrence, jours_semaine, fuseau)
        if prochaine is None or prochaine > maintenant:
            return prochaine
    return None
