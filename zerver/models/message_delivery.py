from django.db import models
from django.db.models import CASCADE

from typing import Any

from zerver.models.messages import Message
from zerver.models.users import UserProfile

class MessageDeliveryStatus(models.Model):
    """Tracks the delivery status of messages to recipients, similar to WhatsApp's delivery system."""
    
    class DeliveryStatus(models.IntegerChoices):
        SENT = 1  # Message has been sent from server
        DELIVERED = 2  # Message has been delivered to recipient's device
        READ = 3  # Message has been read by recipient

    message = models.ForeignKey(Message, on_delete=CASCADE, related_name='delivery_statuses')
    recipient = models.ForeignKey(UserProfile, on_delete=CASCADE, related_name='message_delivery_statuses')
    status = models.PositiveSmallIntegerField(choices=DeliveryStatus.choices, default=DeliveryStatus.SENT)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        unique_together = ('message', 'recipient')
        indexes = [
            models.Index(fields=['message', 'recipient']),
            models.Index(fields=['recipient', 'status']),
        ]

    def __str__(self) -> str:
        return f"Message {self.message.id} to {self.recipient.email}: {self.get_status_display()}" 