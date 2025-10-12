import ballerina/http;
import ballerinax/mongodb;
import ballerina/uuid;
import ballerinax/kafka;
import ballerina/log;
import ballerina/time;

configurable string mongoHost = "localhost";
configurable int mongoPort = 27017;
configurable string mongoDatabase = "db";
configurable string mongoUsername = ?;
configurable string mongoPassword = ?;


configurable string kafkaHost = "localhost:9092";
final string passengerEventsTopic = "passenger_events";
final string ticketEventsTopic = "ticket_events";


type Passenger record {|
    string passengerId?;
    string name;
    string password;
    string phoneNumber;
|};

mongodb:Client mongoDb = check new ({
    connection: {
        serverAddress: {
            host: mongoHost,
            port: mongoPort
        },
        auth: <mongodb:ScramSha256AuthCredential>{
            username: mongoUsername,
            password: mongoPassword,
            database: mongoDatabase
        }
    }
});


kafka:Producer kafkaProducer = check new (kafka:DEFAULT_URL, {
    clientId: "passenger_service_producer"
});


service /passenger on new http:Listener(9010) {

    // Register a new passenger
    resource function post register(@http:Payload Passenger passenger) returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection passengersCollection = check db->getCollection("passengers");

        stream<Passenger, error?> existingPassengers = check passengersCollection->find({"phoneNumber": passenger.phoneNumber});
        Passenger[]|error passengers = from Passenger p in existingPassengers select p;

        if passengers is Passenger[] && passengers.length() > 0 {
            return {"success": false, "message": "phone number already registered"};
        }

        string passengerId = uuid:createRandomUuid();
        passenger.passengerId = passengerId;

        check passengersCollection->insertOne(passenger);

        json event = {
            eventType: "passenger_registered",
            passengerId: passengerId,
            name: passenger.name,
            phoneNumber: passenger.phoneNumber,
            timestamp: time:utcNow().toString()
        };

        check kafkaProducer->send({
            topic: passengerEventsTopic,
            value: event.toJsonString()
        });

        log:printInfo("Produced Kafka event: passenger_registered for " + passenger.name);

        return {
            success: true,
            message: "Passenger registered successfully",
            passengerId: passengerId
        };
    }

    // Passenger login
    resource function post login(string emailE, string passwordE) returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection passengersCollection = check db->getCollection("passengers");

        stream<Passenger, error?> result = check passengersCollection->find({"email": emailE, "password": passwordE});
        Passenger[]|error passengers = from Passenger p in result select p;

        if passengers is Passenger[] && passengers.length() > 0 {
            Passenger p = passengers[0];
            return {success: true, message: "successful login", passengerId: p.passengerId};
        }

        return {success: false, message: "incorrect password or email", passengerId: ()};
    }

    // Get passenger profile
    resource function get profile/[string passengerId]() returns Passenger|http:NotFound|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection passengersCollection = check db->getCollection("passengers");

        Passenger? passenger = check passengersCollection->findOne({"passengerId": passengerId});
        if passenger is Passenger {
            return passenger;
        }
        return http:NOT_FOUND;
    }

    // Update profile
    resource function put profile/[string passengerId](@http:Payload json payload) returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection passengersCollection = check db->getCollection("passengers");

        Passenger? existingPassenger = check passengersCollection->findOne({"passengerId": passengerId});
        if existingPassenger is () {
            return {success: false, message: "Passenger not found"};
        }

        map<json> updateFields = {};
        if (payload.name != ()) {
            updateFields["name"] = check payload.name;
        }
        if (payload.phoneNumber != ()) {
            updateFields["phoneNumber"] = check payload.phoneNumber;
        }

        if updateFields.length() > 0 {
            mongodb:Update update = {"set": updateFields};
            mongodb:UpdateResult updateResult = check passengersCollection->updateOne({"passengerId": passengerId}, update);
            return {success: true, message: "profile updated", modifiedCount: updateResult.modifiedCount};
        }

        return {success: false, message: "No valid fields to update"};
    }

    // Change password
    resource function patch profile/[string passengerId]/password(@http:Payload json payload) returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection passengersCollection = check db->getCollection("passengers");

        string currentPassword = check payload.currentPassword;
        string newPassword = check payload.newPassword;

        Passenger? passenger = check passengersCollection->findOne({"passengerId": passengerId, "password": currentPassword});
        if passenger is () {
            return {success: false, message: "Current password is incorrect"};
        }

        mongodb:Update update = {"set": {"password": newPassword}};
        mongodb:UpdateResult updateResult = check passengersCollection->updateOne({"passengerId": passengerId}, update);
        return {success: true, message: "password changed", modifiedCount: updateResult.modifiedCount};
    }

    // Get passenger tickets
    resource function get tickets/[string passengerId]() returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");

        stream<record {}, error?> result = check ticketsCollection->find({"passengerId": passengerId});
        record {}[]|error tickets = from record {} t in result select t;

        if tickets is record {}[] {
            json response = {
                passengerId: passengerId,
                tickets: <json>tickets,
                count: tickets.length()
            };
            return response;
        }
        return {passengerId: passengerId, tickets: [], count: 0};
    }
}


service /ticketConsumer on new kafka:Listener(kafka:DEFAULT_URL, {
    groupId: "passenger-service-ticket-consumer",
    topics: [ticketEventsTopic]
}) {

    remote function onConsumerRecord(kafka:AnydataConsumerRecord[] messages) returns error? {
        foreach kafka:AnydataConsumerRecord message in messages {
            string msg = check string:fromBytes(<byte[]>message.value);
            log:printInfo("Received Kafka ticket event: " + msg);

            // Example: update passenger DB with new ticket info
            json ticketData = check msg.fromJsonString();
            string passengerId = check ticketData.passengerId;

            mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
            mongodb:Collection ticketsCollection = check db->getCollection("tickets");

            check ticketsCollection->insertOne(check ticketData.ensureType());
            log:printInfo("Ticket added for passengerId: " + passengerId);
        }
    }
}
