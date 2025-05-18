from django.http import HttpRequest, HttpResponse
from django.utils.translation import gettext as _
from zerver.decorator import require_post, authenticated_json_view
from zerver.lib.response import json_success
from zerver.lib.typed_endpoint import typed_endpoint
from zerver.models import Message, UserProfile
from zerver.models.message_delivery import MessageDeliveryStatus

@typed_endpoint
def update_message_delivery_status(
    request: HttpRequest,
    user_profile: UserProfile,
    *,
    message_id: int,
    status: int,
) -> HttpResponse:
    """Update the delivery status of a message for the current user."""
    try:
        message = Message.objects.get(id=message_id)
    except Message.DoesNotExist:
        return json_success({"result": "error", "msg": _("Message not found")})

    try:
        delivery_status = MessageDeliveryStatus.objects.get(
            message=message,
            recipient=user_profile
        )
    except MessageDeliveryStatus.DoesNotExist:
        return json_success({"result": "error", "msg": _("Delivery status not found")})

    if status not in dict(MessageDeliveryStatus.DeliveryStatus.choices):
        return json_success({"result": "error", "msg": _("Invalid status")})

    delivery_status.status = status
    delivery_status.save()
    return json_success({"result": "success"}) 