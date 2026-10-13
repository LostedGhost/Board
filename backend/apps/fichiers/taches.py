"""Tâches de fond des fichiers : transfert vers le fournisseur, effacement."""

import logging
import os
import time

import httpx
from celery import shared_task
from django.db import transaction

from apps.fichiers import stockage
from apps.fichiers.models import Fichier, FournisseurStockage, MorceauTelegram, StatutFichier
from commun.evenements import publier

journal = logging.getLogger(__name__)


def _statut(fichier, statut, erreur=None):
    fichier.statut = statut
    fichier.message_erreur = erreur
    fichier.save(update_fields=["statut", "message_erreur"])
    publier(fichier.element.compte_id, "fichier_statut", fichierId=fichier.element_id, statut=statut)


def _vers_telegram(fichier):
    telegram = stockage.Telegram()
    deja = set(fichier.morceaux.values_list("index", flat=True))  # reprise au premier morceau manquant
    with open(fichier.chemin_temporaire, "rb") as flux:
        index = 0
        while True:
            octets = flux.read(stockage.TAILLE_MORCEAU)
            if not octets:
                break
            if index not in deja:
                message_id, file_id = telegram.envoyer_morceau(f"{fichier.element_id}.{index}", octets)
                MorceauTelegram.objects.create(
                    fichier=fichier,
                    index=index,
                    message_id=message_id,
                    file_id_telegram=file_id,
                    taille_octets=len(octets),
                    sha256=stockage.sha256(octets),
                )
            index += 1


def _vers_lulufiles(fichier):
    lulu = stockage.LuluFiles()
    resultat = lulu.envoyer(fichier.chemin_temporaire, f"{fichier.element_id}.bin")
    fichier.id_lulufiles = resultat["id"]
    fichier.save(update_fields=["id_lulufiles"])
    delai, debut = 1.5, time.monotonic()
    while resultat["status"] not in ("ready", "failed"):
        if time.monotonic() - debut > 1800:
            raise stockage.ErreurStockage("Transfert LuluFiles trop long.")
        time.sleep(delai)
        delai = min(delai * 2, 15)
        resultat = lulu.etat(fichier.id_lulufiles)
    if resultat["status"] == "failed":
        raise stockage.ErreurStockage(resultat.get("error_message") or "Échec du transfert LuluFiles.")


@shared_task(ignore_result=True)
def transferer(fichier_id):
    fichier = Fichier.objects.select_related("element").filter(element_id=fichier_id).first()
    if fichier is None or fichier.statut == StatutFichier.PRET or fichier.element.supprime_le:
        return
    _statut(fichier, StatutFichier.ENVOI_EN_COURS)
    try:
        if fichier.fournisseur == FournisseurStockage.TELEGRAM_DIRECT:
            _vers_telegram(fichier)
        else:
            _vers_lulufiles(fichier)
    except (stockage.ErreurStockage, OSError, httpx.HTTPError) as erreur:
        journal.warning("Transfert du fichier %s en échec : %s", fichier_id, erreur)
        with transaction.atomic():
            _statut(fichier, StatutFichier.ECHEC, str(erreur)[:500])
        return
    chemin = fichier.chemin_temporaire
    with transaction.atomic():
        fichier.chemin_temporaire = None
        fichier.save(update_fields=["chemin_temporaire"])
        _statut(fichier, StatutFichier.PRET)
    if chemin and os.path.exists(chemin):
        os.unlink(chemin)


@shared_task(ignore_result=True)
def effacer_du_stockage(infos):
    try:
        if infos["fournisseur"] == FournisseurStockage.TELEGRAM_DIRECT:
            telegram = stockage.Telegram()
            for message_id in infos["messages"]:
                telegram.supprimer_message(message_id)  # au-delà de 48 h, Telegram refuse : contenu chiffré, clé détruite
        elif infos.get("id_lulufiles"):
            stockage.LuluFiles().supprimer(infos["id_lulufiles"])
    except stockage.ErreurStockage as erreur:
        journal.warning("Effacement chez le fournisseur impossible : %s", erreur)
    chemin = infos.get("chemin")
    if chemin and os.path.exists(chemin):
        os.unlink(chemin)
