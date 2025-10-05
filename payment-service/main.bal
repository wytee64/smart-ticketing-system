import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/random;
import ballerinax/mongodb;

// Types
type Payment record {|
    string paymentId?;
    string ticketId;
    string passengerId;
    decimal amount;
    string paymentMethod;
    string status?;
    string createdAt?;
    string? completedAt;
    string? transactionReference;
|};

type PaymentRequest record {|
    string ticketId;
    string passengerId;
    decimal amount;
    string paymentMethod;
|};

// MongoDB configuration
mongodb:ConnectionConfig mongoConfig = {
    url: "mongodb://wytee:cookingdsa@mongodb:27017",
    database: "payment_db"
};

mongodb:Client mongoClient = check new (mongoConfig);
final string collectionName = "payments";

// HTTP Service
service /payment on new http:Listener(9004) {

    // Process payment
    resource function post process(@http:Payload PaymentRequest paymentReq) returns json|error {
        string paymentId = "PAY" + time:utcNow()[0].toString();

        int randomValue = check random:createIntInRange(1, 11);
        boolean paymentSuccess = randomValue <= 9;

        string status = paymentSuccess ? "COMPLETED" : "FAILED";
        string currentTime = time:utcToString(time:utcNow());

        Payment payment = {
            paymentId: paymentId,
            ticketId: paymentReq.ticketId,
            passengerId: paymentReq.passengerId,
            amount: paymentReq.amount,
            paymentMethod: paymentReq.paymentMethod,
            status: status,
            createdAt: currentTime,
            completedAt: paymentSuccess ? currentTime : (),
            transactionReference: paymentSuccess ? "TXN" + time:utcNow()[0].toString() : ()
        };

        // Insert into Mongo
        check mongoClient->insertOne(collectionName, payment.toJson());

        if paymentSuccess {
            log:printInfo("Payment completed: " + paymentId);

            // Update ticket status to PAID
            http:Client ticketingClient = check new("http://ticketing-service:9003");
            json|error updateResult = ticketingClient->put("/ticketing/" + paymentReq.ticketId + "/pay", {});

            if updateResult is error {
                log:printError("Failed to update ticket status", updateResult);
            }
        } else {
            log:printWarn("Payment failed: " + paymentId);
        }

        return {
            "success": paymentSuccess,
            "message": paymentSuccess ? "Payment completed successfully" : "Payment failed",
            "paymentId": paymentId,
            "status": status,
            "transactionReference": payment.transactionReference
        };
    }

    // Get payment details by paymentId
    resource function get [string paymentId]() returns Payment|http:NotFound|error {
        json? result = check mongoClient->findOne(collectionName, { "paymentId": paymentId });
        if result is json {
            return <Payment>result;
        }
        return http:NOT_FOUND;
    }

    // Get payment history for passenger
    resource function get passenger/[string passengerId]() returns json|error {
        json[] passengerPayments = check mongoClient->find(collectionName, { "passengerId": passengerId });
        return {
            "passengerId": passengerId,
            "payments": passengerPayments
        };
    }

    // Health check
    resource function get health() returns json {
        return {
            "service": "payment-service",
            "status": "UP",
            "timestamp": time:utcToString(time:utcNow())
        };
    }
}
