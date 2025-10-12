import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerina/lang.runtime;
import ballerinax/kafka;

// ---------- Config ----------
configurable string kafkaBootstrapServers = "kafka:9092"; // inside Docker; use localhost:9092 if running locally

// ---------- Request/Response DTOs ----------
type NotificationRequest record {|
    string passengerId;
    string message;
    string channel; // "EMAIL" | "SMS" | "PUSH"
|};

type NotificationResponse record {|
    string notificationId;
    string message;
|};

// ---------- Kafka consumers (3 topics like your friend) ----------
final kafka:Consumer paymentsConsumer = check new (kafkaBootstrapServers, {
    groupId: "notification-service-payments",
    topics: ["payments.processed"],
    offsetReset: "earliest",
    autoCommit: false
});

final kafka:Consumer ticketsConsumer = check new (kafkaBootstrapServers, {
    groupId: "notification-service-tickets",
    topics: ["ticket.validated"],
    offsetReset: "earliest",
    autoCommit: false
});

final kafka:Consumer disruptionsConsumer = check new (kafkaBootstrapServers, {
    groupId: "notification-service-disruptions",
    topics: ["service.disruptions"],
    offsetReset: "earliest",
    autoCommit: false
});

// ---------- simple in-memory stats ----------
int totalNotificationsSent = 0;
int paymentNotifications = 0;
int ticketNotifications = 0;
int disruptionNotifications = 0;

// ---------- background workers that poll Kafka ----------
function startConsumers() returns error? {

    worker PaymentsWorker returns error? {
        while true {
            kafka:BytesConsumerRecord[]|error records = paymentsConsumer->poll(1);
            if records is kafka:BytesConsumerRecord[] {
                foreach var r in records {
                    byte[] body = r.value;
                    string msg = check string:fromBytes(body);
                    log:printInfo("Payment notification: " + msg);

                    // simulate “sending” a real notification
                    totalNotificationsSent += 1;
                    paymentNotifications += 1;

                    check paymentsConsumer->commit();
                }
            }
            runtime:sleep(1);
        }
    }

    worker TicketsWorker returns error? {
        while true {
            kafka:BytesConsumerRecord[]|error records = ticketsConsumer->poll(1);
            if records is kafka:BytesConsumerRecord[] {
                foreach var r in records {
                    byte[] body = r.value;
                    string msg = check string:fromBytes(body);
                    log:printInfo("Ticket validation notification: " + msg);

                    totalNotificationsSent += 1;
                    ticketNotifications += 1;

                    check ticketsConsumer->commit();
                }
            }
            runtime:sleep(1);
        }
    }

    worker DisruptionsWorker returns error? {
        while true {
            kafka:BytesConsumerRecord[]|error records = disruptionsConsumer->poll(1);
            if records is kafka:BytesConsumerRecord[] {
                foreach var r in records {
                    byte[] body = r.value;
                    string msg = check string:fromBytes(body);
                    log:printInfo("Service disruption notification: " + msg);

                    totalNotificationsSent += 1;
                    disruptionNotifications += 1;

                    check disruptionsConsumer->commit();
                }
            }
            runtime:sleep(1);
        }
    }
}

// ---------- HTTP service (port 9010) ----------
service /notifications on new http:Listener(9010) {

    // start workers when service starts
    function init() returns error? {
        check startConsumers();
        log:printInfo("Notification Service started. Listening to Kafka topics…");
    }

    resource function get health() returns string {
        return "OK";
    }

    // manual send (for testing)
    resource function post send(@http:Payload NotificationRequest req)
            returns NotificationResponse|http:Response|error {
        totalNotificationsSent += 1;
        log:printInfo(string `Sending ${req.channel} notification to ${req.passengerId}: ${req.message}`);
        return { notificationId: uuid:createType1AsString(), message: "Notification enqueued (simulated)" };
    }

    // stats (like your friend’s)
    resource function get stats() returns json {
        return {
            "totalNotifications": totalNotificationsSent,
            "paymentNotifications": paymentNotifications,
            "ticketNotifications": ticketNotifications,
            "disruptionNotifications": disruptionNotifications,
            "message": "Notification statistics retrieved"
        };
    }
}
