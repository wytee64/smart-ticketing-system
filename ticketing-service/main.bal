import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerinax/mongodb;
import ballerina/uuid;

configurable string mongoHost = "localhost";
configurable int mongoPort = 27017;
configurable string mongoDatabase = "db";
configurable string mongoUsername = ?;
configurable string mongoPassword = ?;

// Types
type Ticket record {|
    string ticketId?;
    string passengerId;
    string ticketType;
    string? routeId;
    decimal amount?;
    string status?;
    string createdAt?;
    string? validatedAt;
    string? expiresAt;
    int? ridesRemaining;
|};

type TicketRequest record {|
    string passengerId;
    string ticketType;
    string? routeId;
    int? numberOfRides;
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

// HTTP Service
service /ticketing on new http:Listener(9003) {

    // Create ticket request
    resource function post request(@http:Payload TicketRequest ticketReq) returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");

        decimal amount = check calculateTicketAmount(ticketReq.ticketType, ticketReq.numberOfRides);

        string ticketId = uuid:createType1AsString();
        string? expiresAt = calculateExpiryDate(ticketReq.ticketType);

        Ticket ticket = {
            ticketId: ticketId,
            passengerId: ticketReq.passengerId,
            ticketType: ticketReq.ticketType,
            routeId: ticketReq.routeId,
            amount: amount,
            status: "CREATED",
            createdAt: time:utcToString(time:utcNow()),
            validatedAt: (),
            expiresAt: expiresAt,
            ridesRemaining: ticketReq.numberOfRides
        };

        check ticketsCollection->insertOne(ticket);

        log:printInfo("Ticket created: " + ticketId);

        return {
            "success": true,
            "message": "Ticket created successfully",
            "ticketId": ticketId,
            "amount": amount,
            "status": "CREATED"
        };
    }

    // Validate ticket
    resource function post validate/[string ticketId](@http:Payload json validationData) returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");

        Ticket? ticket = check ticketsCollection->findOne({"ticketId": ticketId});
        
        if ticket is () {
            return {
                "success": false,
                "message": "Ticket not found"
            };
        }

        if (ticket.status != "PAID" && ticket.status != "CREATED") {
            return {
                "success": false,
                "message": "Ticket cannot be validated. Status: " + (ticket.status ?: "UNKNOWN")
            };
        }

        // Update ticket status to VALIDATED
        map<json> updateFields = {
            "status": "VALIDATED",
            "validatedAt": time:utcToString(time:utcNow())
        };

        // Decrement rides for multiple ride tickets
        if (ticket.ticketType == "MULTIPLE_RIDES" && ticket.ridesRemaining is int) {
            int remainingRides = <int>ticket.ridesRemaining - 1;
            updateFields["ridesRemaining"] = remainingRides;
            if (remainingRides > 0) {
                updateFields["status"] = "PAID";
            }
        }

        mongodb:Update update = {"set": updateFields};
        mongodb:UpdateResult updateResult = check ticketsCollection->updateOne({"ticketId": ticketId}, update);

        log:printInfo("Ticket validated: " + ticketId);

        return {
            "success": true,
            "message": "Ticket validated successfully",
            "ticketId": ticketId,
            "modifiedCount": updateResult.modifiedCount
        };
    }

    // Get ticket details
    resource function get [string ticketId]() returns Ticket|http:NotFound|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");

        Ticket? ticket = check ticketsCollection->findOne({"ticketId": ticketId});
        if ticket is Ticket {
            return ticket;
        }
        return http:NOT_FOUND;
    }

    // Update ticket status to PAID (simulating payment confirmation)
    resource function put [string ticketId]/pay() returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");

        Ticket? existingTicket = check ticketsCollection->findOne({"ticketId": ticketId});
        if existingTicket is () {
            return {
                "success": false,
                "message": "Ticket not found"
            };
        }

        mongodb:Update update = {"set": {"status": "PAID"}};
        mongodb:UpdateResult updateResult = check ticketsCollection->updateOne({"ticketId": ticketId}, update);
        
        return {
            "success": true,
            "message": "Ticket marked as PAID",
            "modifiedCount": updateResult.modifiedCount
        };
    }

    // Get all tickets for a passenger
    resource function get passenger/[string passengerId]() returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");

        stream<Ticket, error?> result = check ticketsCollection->find({"passengerId": passengerId});
        Ticket[]|error tickets = from Ticket t in result select t;

        if tickets is Ticket[] {
            return {
                passengerId: passengerId,
                tickets: <json>tickets,
                count: tickets.length()
            };
        }

        return {passengerId: passengerId, tickets: [], count: 0};
    }

    // Health check
    resource function get health() returns json {
        return {
            "service": "ticketing-service",
            "status": "UP",
            "timestamp": time:utcToString(time:utcNow())
        };
    }
}

// Utility functions
function calculateTicketAmount(string ticketType, int? numberOfRides) returns decimal|error {
    match ticketType {
        "SINGLE_RIDE" => {
            return 15.00;
        }
        "MULTIPLE_RIDES" => {
            int rides = numberOfRides ?: 10;
            return <decimal>rides * 12d;
        }
        "MONTHLY_PASS" => {
            return 250.00;
        }
        "ANNUAL_PASS" => {
            return 2500.00;
        }
        _ => {
            return error("Invalid ticket type");
        }
    }
}

function calculateExpiryDate(string ticketType) returns string? {
    match ticketType {
        "SINGLE_RIDE"|"MULTIPLE_RIDES" => {
            time:Utc expiryTime = time:utcAddSeconds(time:utcNow(), 30 * 24 * 3600);
            return time:utcToString(expiryTime);
        }
        "MONTHLY_PASS" => {
            time:Utc expiryTime = time:utcAddSeconds(time:utcNow(), 30 * 24 * 3600);
            return time:utcToString(expiryTime);
        }
        "ANNUAL_PASS" => {
            time:Utc expiryTime = time:utcAddSeconds(time:utcNow(), 365 * 24 * 3600);
            return time:utcToString(expiryTime);
        }
        _ => {
            return ();
        }
    }
}
