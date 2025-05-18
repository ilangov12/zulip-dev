from typing import List
from django.db import transaction
from zerver.models import Message, MessageDeliveryStatus, UserProfile

def create_initial_delivery_status(message: Message, recipients: List[UserProfile]) -> None:
    """Create initial delivery status records for a message and its recipients."""
    delivery_statuses = [
        MessageDeliveryStatus(
            message=message,
            recipient=recipient,
            status=MessageDeliveryStatus.DeliveryStatus.SENT
        )
        for recipient in recipients
    ]
    MessageDeliveryStatus.objects.bulk_create(delivery_statuses)

def update_delivery_status(
    message: Message,
    recipient: UserProfile,
    status: MessageDeliveryStatus.DeliveryStatus
) -> None:
    """Update the delivery status for a specific message and recipient."""
    with transaction.atomic():
        delivery_status = MessageDeliveryStatus.objects.select_for_update().get(
            message=message,
            recipient=recipient
        )
        delivery_status.status = status
        delivery_status.save()

def get_message_delivery_statuses(message: Message) -> List[MessageDeliveryStatus]:
    """Get all delivery statuses for a message."""
    return MessageDeliveryStatus.objects.filter(message=message).select_related('recipient')

def get_recipient_delivery_statuses(recipient: UserProfile) -> List[MessageDeliveryStatus]:
    """Get all delivery statuses for a recipient."""
    return MessageDeliveryStatus.objects.filter(recipient=recipient).select_related('message') 