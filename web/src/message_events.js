// Add the following functions to handle message delivery status and deleted messages

function update_message_delivery_status(message_id, status) {
    // Send status update to server
    channel.post({
        url: '/json/messages/' + message_id + '/delivery_status',
        data: {status: status},
        success: function() {
            // Update UI if needed
            if (status === 3) { // READ status
                $("[data-message-id='" + message_id + "'] .delivery-status")
                    .removeClass("sent delivered")
                    .addClass("read");
            } else if (status === 2) { // DELIVERED status
                $("[data-message-id='" + message_id + "'] .delivery-status")
                    .removeClass("sent")
                    .addClass("delivered");
            }
        },
    });
}

function mark_messages_as_read(messages) {
    // Mark messages as read when they appear in the viewport
    for (const message of messages) {
        // Only update for messages sent to the current user
        if (message.sent_by_me === false) {
            update_message_delivery_status(message.id, 3); // READ status
        }
    }
}

function handle_deleted_message(message_id) {
    // Add deleted message indicator
    const $msg_container = $("[data-message-id='" + message_id + "']");
    $msg_container.find(".message-content").html(
        '<div class="message-deleted-indicator"><i class="fa fa-times"></i> This message was deleted</div>'
    );
    $msg_container.addClass("deleted-message");
}

// Add these to the existing initialization
$(function () {
    // Handle message visibility to update read status
    const observer = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
            if (entry.isIntersecting) {
                const message_id = $(entry.target).data("message-id");
                if (message_id) {
                    // Update read status for visible messages
                    update_message_delivery_status(message_id, 3); // READ status
                }
            }
        });
    }, { threshold: 0.5 });
    
    // Observe all incoming messages
    function observe_new_messages() {
        $(".message_row").each(function() {
            observer.observe(this);
        });
    }
    
    // Set up observer for new messages
    observe_new_messages();
    
    // Re-observe when messages are added
    $(document).on("message_rendered.zulip", function() {
        observe_new_messages();
    });
});

// ... existing code ... 