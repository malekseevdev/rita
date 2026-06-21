from app import metrics

# Per-client request ceiling, requests per minute.
LIMIT_PER_MINUTE = 60


def allow(client_id, window):
    """Return True if the client is under the limit for this window."""
    count = window.count(client_id)
    if count >= LIMIT_PER_MINUTE:
        metrics.incr("svc.throttle.rejected")
        return False
    return True
