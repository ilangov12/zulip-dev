from django.urls import path
from zerver.views import update_message_delivery_status

urlpatterns = [
    # ... existing patterns ...
    
    # Message delivery status API
    path("json/messages/<int:message_id>/delivery_status", 
         update_message_delivery_status),
         
    # ... more patterns ...
] 