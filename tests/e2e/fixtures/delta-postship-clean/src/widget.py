import os

from app import metrics

# Toggle the fast rendering path.
FAST = os.environ.get("FEATURE_WIDGET_FAST", "0") == "1"


def process(widget):
    """Render a widget and record the outcome."""
    result = _render(widget, fast=FAST)
    metrics.incr("svc.widget.processed")
    return result


def _render(widget, fast):
    return widget.upper() if not fast else widget
