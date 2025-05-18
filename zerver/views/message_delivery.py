from django.http import HttpRequest, HttpResponse
from django.utils.translation import gettext as _
from zerver.decorator import require_post, authenticated_json_view
from zerver.lib.request import REQ, has_request_variables
from zerver.lib.response import json_success
from zerver.lib.message_delivery import update_delivery_status
from zerver.models import Message, MessageDeliveryStatus, UserProfile

@authenticated_json_view
@has_request_variables
def update_message_delivery_status(
    request: HttpRequest,
    user_profile: UserProfile,
    message_id: int = REQ(converter=int),
    status: int = REQ(converter=int),
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

    update_delivery_status(message, user_profile, status)
    return json_success({"result": "success"}) 