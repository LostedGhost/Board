"""Identifiant de requête (X-Request-ID), propagé dans les réponses et les journaux."""

import contextvars
import logging
import re
import uuid

_request_id = contextvars.ContextVar("request_id", default="-")
_FORMAT_ACCEPTE = re.compile(r"^[A-Za-z0-9-]{8,64}$")


def request_id_courant():
    return _request_id.get()


class RequestIdMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        recu = request.headers.get("X-Request-ID", "")
        rid = recu if _FORMAT_ACCEPTE.match(recu) else uuid.uuid4().hex[:16]
        jeton = _request_id.set(rid)
        try:
            request.request_id = rid
            response = self.get_response(request)
            response["X-Request-ID"] = rid
            return response
        finally:
            _request_id.reset(jeton)


class FiltreRequestId(logging.Filter):
    def filter(self, record):
        record.request_id = request_id_courant()
        return True
