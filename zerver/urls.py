from django.urls import path
from zerver.views.message_delivery import update_message_delivery_status

# Include these URL patterns in your main urlpatterns list
message_delivery_urls = [
    path("messages/<int:message_id>/delivery_status", update_message_delivery_status),
]

urlpatterns = [
    # ... existing patterns ...
    
    # Message delivery status API
    path("json/messages/<int:message_id>/delivery_status", 
         update_message_delivery_status),
         
    # ... more patterns ...
] 