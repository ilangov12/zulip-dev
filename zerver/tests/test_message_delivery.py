from django.test import TestCase
from django.utils import timezone
from zerver.models import (
    Message,
    MessageDeliveryStatus,
    UserProfile,
    Recipient,
    Stream,
    get_realm,
    get_stream,
)
from zerver.lib.test_classes import ZulipTestCase
from zerver.lib.test_helpers import get_test_image_file
from zerver.lib.actions import do_send_messages
from zerver.lib.message import get_messages_for_narrow
from django.urls import reverse

class MessageDeliveryStatusTest(ZulipTestCase):
    def setUp(self):
        super().setUp()
        self.user1 = self.example_user("hamlet")
        self.user2 = self.example_user("othello")
        self.stream = get_stream("Verona", self.user1.realm)
        self.recipient = Recipient.objects.get(type_id=self.stream.id, type=Recipient.STREAM)

    def test_message_delivery_status_creation(self):
        """Test that delivery status is created when a message is sent"""
        message = do_send_messages(
            self.user1,
            [{
                "type": "stream",
                "to": "Verona",
                "content": "Test message",
                "topic": "Test topic",
            }]
        )[0]

        # Check that delivery status was created for all recipients
        delivery_statuses = MessageDeliveryStatus.objects.filter(message=message)
        self.assertTrue(delivery_statuses.exists())
        
        # Verify initial status is SENT
        for status in delivery_statuses:
            self.assertEqual(status.status, MessageDeliveryStatus.DeliveryStatus.SENT)

    def test_update_delivery_status(self):
        """Test updating message delivery status"""
        message = do_send_messages(
            self.user1,
            [{
                "type": "stream",
                "to": "Verona",
                "content": "Test message",
                "topic": "Test topic",
            }]
        )[0]

        # Get delivery status for user2
        delivery_status = MessageDeliveryStatus.objects.get(
            message=message,
            recipient=self.user2
        )

        # Update status to DELIVERED
        delivery_status.status = MessageDeliveryStatus.DeliveryStatus.DELIVERED
        delivery_status.save()

        # Verify status was updated
        updated_status = MessageDeliveryStatus.objects.get(
            message=message,
            recipient=self.user2
        )
        self.assertEqual(
            updated_status.status,
            MessageDeliveryStatus.DeliveryStatus.DELIVERED
        )

        # Update status to READ
        delivery_status.status = MessageDeliveryStatus.DeliveryStatus.READ
        delivery_status.save()

        # Verify final status
        final_status = MessageDeliveryStatus.objects.get(
            message=message,
            recipient=self.user2
        )
        self.assertEqual(
            final_status.status,
            MessageDeliveryStatus.DeliveryStatus.READ
        )

    def test_delivery_status_unique_constraint(self):
        """Test that we can't create duplicate delivery status records"""
        message = do_send_messages(
            self.user1,
            [{
                "type": "stream",
                "to": "Verona",
                "content": "Test message",
                "topic": "Test topic",
            }]
        )[0]

        # Try to create duplicate delivery status
        with self.assertRaises(Exception):
            MessageDeliveryStatus.objects.create(
                message=message,
                recipient=self.user2,
                status=MessageDeliveryStatus.DeliveryStatus.SENT
            )

    def test_delivery_status_timestamps(self):
        """Test that timestamps are properly updated"""
        message = do_send_messages(
            self.user1,
            [{
                "type": "stream",
                "to": "Verona",
                "content": "Test message",
                "topic": "Test topic",
            }]
        )[0]

        delivery_status = MessageDeliveryStatus.objects.get(
            message=message,
            recipient=self.user2
        )
        initial_timestamp = delivery_status.updated_at

        # Update status
        delivery_status.status = MessageDeliveryStatus.DeliveryStatus.DELIVERED
        delivery_status.save()

        # Verify timestamp was updated
        updated_status = MessageDeliveryStatus.objects.get(
            message=message,
            recipient=self.user2
        )
        self.assertGreater(updated_status.updated_at, initial_timestamp)

class MessageDeliveryAPITest(ZulipTestCase):
    def test_update_delivery_status(self) -> None:
        """Test updating message delivery status via API."""
        sender = self.example_user("hamlet")
        recipient = self.example_user("othello")
        
        # Send a message
        message_id = self.send_personal_message(
            sender,
            recipient,
            "Test message",
        )
        
        # Try to update delivery status
        result = self.api_post(
            recipient,
            f"/api/v1/messages/{message_id}/delivery_status",
            {"status": MessageDeliveryStatus.DeliveryStatus.DELIVERED},
        )
        self.assert_json_success(result)
        
        # Verify the status was updated
        delivery_status = MessageDeliveryStatus.objects.get(
            message_id=message_id,
            recipient=recipient
        )
        self.assertEqual(delivery_status.status, MessageDeliveryStatus.DeliveryStatus.DELIVERED)
        
    def test_update_nonexistent_message(self) -> None:
        """Test updating status for a nonexistent message."""
        recipient = self.example_user("othello")
        
        result = self.api_post(
            recipient,
            "/api/v1/messages/999999/delivery_status",
            {"status": MessageDeliveryStatus.DeliveryStatus.DELIVERED},
        )
        self.assert_json_error(result, "Message not found")
        
    def test_update_invalid_status(self) -> None:
        """Test updating with an invalid status."""
        sender = self.example_user("hamlet")
        recipient = self.example_user("othello")
        
        # Send a message
        message_id = self.send_personal_message(
            sender,
            recipient,
            "Test message",
        )
        
        # Try to update with invalid status
        result = self.api_post(
            recipient,
            f"/api/v1/messages/{message_id}/delivery_status",
            {"status": 999},
        )
        self.assert_json_error(result, "Invalid status")
        
    def test_update_other_user_message(self) -> None:
        """Test updating status for another user's message."""
        sender = self.example_user("hamlet")
        recipient = self.example_user("othello")
        other_user = self.example_user("cordelia")
        
        # Send a message
        message_id = self.send_personal_message(
            sender,
            recipient,
            "Test message",
        )
        
        # Try to update status as another user
        result = self.api_post(
            other_user,
            f"/api/v1/messages/{message_id}/delivery_status",
            {"status": MessageDeliveryStatus.DeliveryStatus.DELIVERED},
        )
        self.assert_json_error(result, "Delivery status not found") 