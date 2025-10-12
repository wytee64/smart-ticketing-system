import ballerina/http;
import ballerina/uuid;
import ballerina/time;
import ballerinax/mongodb;
import ballerinax/kafka;

// MongoDB configuration (aligned with ticket service)
configurable string mongoHost = "mongodb";
configurable int mongoPort = 27017;
configurable string mongoDatabase = "db"; // <-- aligned with ticket service

// Kafka configuration
configurable string kafkaBootstrapServers = "kafka:29092";

// MongoDB client
final mongodb:Client mongoDb = check new ({
    connection: {
        serverAddress: {
            host: mongoHost,
            port: mongoPort
        }
    }
});

// Kafka producer for payment events
final kafka:Producer kafkaProducer = check new (kafkaBootstrapServers, {
    clientId: "payment-service-producer",
    acks: "1",
    retryCount: 3,
    maxBlock: 5000,
    requestTimeout: 5000
});

// Payment record type
type Payment record {|
    string _id;
    string ticketId;
    string passengerId;
    decimal amount;
    string method; // CARD, MOBILE_MONEY, CASH
    string status; // INITIATED, CONFIRMED, FAILED, REFUNDED
    string createdAt;
    string? processedAt;
|};

// Request types
type CreatePaymentRequest record {|
    string ticketId;
    string passengerId;
    decimal amount;
    string method;
|};

type RefundRequest record {|
    string reason;
|};

// Response types
type PaymentResponse record {|
    string paymentId;
    string ticketId;
    string passengerId;
    decimal amount;
    string method;
    string status;
    string createdAt;
    string? processedAt;
    string message;
|};

service /payments on new http:Listener(8084) {

    resource function get health() returns string {
        return "OK";
    }

    resource function post .(@http:Payload CreatePaymentRequest request)
            returns PaymentResponse|http:Response|error {

        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection paymentsCollection = check db->getCollection("payments");

        string paymentId = uuid:createType1AsString();
        string currentTime = time:utcToString(time:utcNow());

        Payment newPayment = {
            _id: paymentId,
            ticketId: request.ticketId,
            passengerId: request.passengerId,
            amount: request.amount,
            method: request.method,
            status: "CONFIRMED",
            createdAt: currentTime,
            processedAt: currentTime
        };

        check paymentsCollection->insertOne(newPayment);

        json paymentEvent = {
            "paymentId": paymentId,
            "ticketId": request.ticketId,
            "passengerId": request.passengerId,
            "amount": request.amount,
            "status": "CONFIRMED",
            "timestamp": currentTime
        };

        check kafkaProducer->send({
            topic: "payments.processed",
            value: paymentEvent.toString().toBytes()
        });

        return {
            paymentId: paymentId,
            ticketId: request.ticketId,
            passengerId: request.passengerId,
            amount: request.amount,
            method: request.method,
            status: "CONFIRMED",
            createdAt: currentTime,
            processedAt: currentTime,
            message: "Payment processed successfully"
        };
    }

    resource function get [string paymentId]() returns Payment|http:Response|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection paymentsCollection = check db->getCollection("payments");

        stream<Payment, error?> paymentStream = check paymentsCollection->find({_id: paymentId});
        Payment[]? payments = check from Payment p in paymentStream select p;

        if payments is () || payments.length() == 0 {
            http:Response res = new;
            res.statusCode = 404;
            res.setJsonPayload({message: "Payment not found"});
            return res;
        }

        return payments[0];
    }

    resource function get ticket/[string ticketId]() returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection paymentsCollection = check db->getCollection("payments");

        int paymentCount = check paymentsCollection->countDocuments({ticketId: ticketId});

        return {
            "ticketId": ticketId,
            "totalPayments": paymentCount,
            "message": "Payment data retrieved"
        };
    }

    resource function post [string paymentId]/refund(@http:Payload RefundRequest request)
            returns json|http:Response|error {

        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection paymentsCollection = check db->getCollection("payments");

        stream<Payment, error?> paymentStream = check paymentsCollection->find({_id: paymentId});
        Payment[]? payments = check from Payment p in paymentStream select p;

        if payments is () || payments.length() == 0 {
            http:Response res = new;
            res.statusCode = 404;
            res.setJsonPayload({message: "Payment not found"});
            return res;
        }

        Payment payment = payments[0];

        if payment.status != "CONFIRMED" {
            http:Response res = new;
            res.statusCode = 400;
            res.setJsonPayload({message: "Only confirmed payments can be refunded"});
            return res;
        }

        string refundTime = time:utcToString(time:utcNow());

        mongodb:UpdateResult _ = check paymentsCollection->updateOne(
            {_id: paymentId},
            {set: {status: "REFUNDED", processedAt: refundTime}}
        );

        json refundEvent = {
            "paymentId": paymentId,
            "ticketId": payment.ticketId,
            "passengerId": payment.passengerId,
            "amount": payment.amount,
            "status": "REFUNDED",
            "reason": request.reason,
            "timestamp": refundTime
        };

        check kafkaProducer->send({
            topic: "payments.processed",
            value: refundEvent.toString().toBytes()
        });

        return {
            "paymentId": paymentId,
            "status": "REFUNDED",
            "refundedAt": refundTime,
            "reason": request.reason,
            "message": "Payment refunded successfully"
        };
    }

    resource function get all() returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection paymentsCollection = check db->getCollection("payments");

        int totalPayments = check paymentsCollection->countDocuments({});
        int confirmedPayments = check paymentsCollection->countDocuments({status: "CONFIRMED"});
        int refundedPayments = check paymentsCollection->countDocuments({status: "REFUNDED"});

        return {
            "totalPayments": totalPayments,
            "confirmedPayments": confirmedPayments,
            "refundedPayments": refundedPayments,
            "message": "Payment statistics retrieved"
        };
    }
}
