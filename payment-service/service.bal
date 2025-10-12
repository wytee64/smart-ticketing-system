import ballerina/http;
import ballerina/uuid;
import ballerina/time;
import ballerinax/mongodb;
import ballerinax/kafka;

configurable string mongoHost = "localhost";
configurable int mongoPort = 27017;
configurable string mongoDatabase = "db";
configurable string kafkaBootstrapServers = "localhost:9092";


final mongodb:Client mongoDb = check new ({
    connection: { serverAddress: { host: mongoHost, port: mongoPort } }
});

final kafka:Producer kafkaProducer = check new (kafkaBootstrapServers, {
    clientId: "payment-service-producer",
    acks: "1", retryCount: 3, maxBlock: 5000, requestTimeout: 5000
});

type Payment record {|
    string _id;
    string ticketId;
    string passengerId;
    decimal amount;
    string method;
    string status;
    string createdAt;
    string? processedAt;
|};

type CreatePaymentRequest record {|
    string ticketId;
    string passengerId;
    decimal amount;
    string method;
|};

type RefundRequest record {|
    string reason;
|};

service /payments on new http:Listener(8084) {

    resource function get health() returns string => "OK";

    resource function post .(@http:Payload CreatePaymentRequest req)
            returns json|http:Response|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection coll = check db->getCollection("payments");

        string id = uuid:createType1AsString();
        string now = time:utcToString(time:utcNow());

        Payment payment = {
            _id: id, ticketId: req.ticketId, passengerId: req.passengerId,
            amount: req.amount, method: req.method, status: "CONFIRMED",
            createdAt: now, processedAt: now
        };

        check coll->insertOne(payment);

        json event = {
            paymentId: id, ticketId: req.ticketId, passengerId: req.passengerId,
            amount: req.amount, status: "CONFIRMED", timestamp: now
        };

        check kafkaProducer->send({
            topic: "payments.processed",
            value: event.toString().toBytes()
        });

        return payment.cloneReadOnly();
    }

    resource function get [string id]() returns Payment|http:Response|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection coll = check db->getCollection("payments");

        stream<Payment, error?> results = check coll->find({ _id: id });
        Payment[] payments = check from Payment p in results select p;

        if payments.length() == 0 {
            http:Response res = new;
            res.statusCode = 404;
            res.setJsonPayload({ message: "Payment not found" });
            return res;
        }
        return payments[0];
    }

    resource function post [string id]/refund(@http:Payload RefundRequest req)
            returns json|http:Response|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection coll = check db->getCollection("payments");

        stream<Payment, error?> s = check coll->find({ _id: id });
        Payment[] payments = check from Payment p in s select p;

        if payments.length() == 0 {
            http:Response res = new;
            res.statusCode = 404;
            res.setJsonPayload({ message: "Payment not found" });
            return res;
        }

        Payment p = payments[0];
        if p.status != "CONFIRMED" {
            http:Response res = new;
            res.statusCode = 400;
            res.setJsonPayload({ message: "Only confirmed payments can be refunded" });
            return res;
        }

        string now = time:utcToString(time:utcNow());
        _ = check coll->updateOne({ _id: id }, { "$set": { status: "REFUNDED", processedAt: now } });

        json event = {
            paymentId: id, ticketId: p.ticketId, passengerId: p.passengerId,
            amount: p.amount, status: "REFUNDED", reason: req.reason, timestamp: now
        };
        check kafkaProducer->send({
            topic: "payments.processed",
            value: event.toString().toBytes()
        });

        return { paymentId: id, status: "REFUNDED", refundedAt: now, message: "Payment refunded" };
    }

    resource function get all() returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection coll = check db->getCollection("payments");

        int total = check coll->countDocuments({});
        int confirmed = check coll->countDocuments({ status: "CONFIRMED" });
        int refunded = check coll->countDocuments({ status: "REFUNDED" });

        return { total, confirmed, refunded };
    }
}
