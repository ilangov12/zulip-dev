from django.http import HttpRequest, HttpResponse
from django.utils.translation import gettext as _
from zerver.decorator import require_post, authenticated_json_view
from zerver.lib.response import json_success
from zerver.lib.typed_endpoint import typed_endpoint
from zerver.models import Message, UserProfile
from zerver.models.message_delivery import MessageDeliveryStatus

@typed_endpoint
@require_post
@authenticated_json_view
def update_message_delivery_status(
    request: HttpRequest,
    user_profile: UserProfile,
    *,
    message_id: int,
) -> HttpResponse:
    """Update the delivery status of a message for the current user."""
    try:
        message = Message.objects.get(id=message_id)
    except Message.DoesNotExist:
        return json_success({"result": "error", "msg": _("Message not found")})

    status = int(request.POST.get("status", 1))
    
    try:
        delivery_status, created = MessageDeliveryStatus.objects.get_or_create(
            message=message,
            recipient=user_profile,
            defaults={"status": status}
        )
        
        if not created and status > delivery_status.status:
            delivery_status.status = status
            delivery_status.save()
            
    except Exception as e:
        return json_success({"result": "error", "msg": str(e)})

    return json_success({"result": "success"}) 