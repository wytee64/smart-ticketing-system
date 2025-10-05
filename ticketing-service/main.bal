import ballerina/http;
import ballerina/log;
import ballerina/time;

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

// In-memory storage
map<Ticket> tickets = {};

// HTTP Service
service /ticketing on new http:Listener(9003) {

    // Create ticket request
    resource function post request(@http:Payload TicketRequest ticketReq) returns json|error {
        decimal amount = check calculateTicketAmount(ticketReq.ticketType, ticketReq.numberOfRides);

        string ticketId = "TKT" + time:utcNow()[0].toString();

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

        tickets[ticketId] = ticket;

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
        if (!tickets.hasKey(ticketId)) {
            return {
                "success": false,
                "message": "Ticket not found"
            };
        }

        Ticket ticket = tickets.get(ticketId);

        if (ticket.status != "PAID" && ticket.status != "CREATED") {
            return {
                "success": false,
                "message": "Ticket cannot be validated. Status: " + (ticket.status ?: "UNKNOWN")
            };
        }

        // Update ticket status to VALIDATED
        ticket.status = "VALIDATED";
        ticket.validatedAt = time:utcToString(time:utcNow());

        // Decrement rides for multiple ride tickets
        if (ticket.ticketType == "MULTIPLE_RIDES" && ticket.ridesRemaining is int) {
            int remainingRides = <int>ticket.ridesRemaining - 1;
            ticket.ridesRemaining = remainingRides;
            if (remainingRides > 0) {
                ticket.status = "PAID";
            }
        }

        tickets[ticketId] = ticket;

        log:printInfo("Ticket validated: " + ticketId);

        return {
            "success": true,
            "message": "Ticket validated successfully",
            "ticketId": ticketId
        };
    }

    // Get ticket details
    resource function get [string ticketId]() returns Ticket|http:NotFound|error {
        if (tickets.hasKey(ticketId)) {
            return tickets.get(ticketId);
        }
        return http:NOT_FOUND;
    }

    // Update ticket status to PAID (simulating payment confirmation)
    resource function put [string ticketId]/pay() returns json|error {
        if (tickets.hasKey(ticketId)) {
            Ticket ticket = tickets.get(ticketId);
            ticket.status = "PAID";
            tickets[ticketId] = ticket;
            
            return {
                "success": true,
                "message": "Ticket marked as PAID"
            };
        }
        return {
            "success": false,
            "message": "Ticket not found"
        };
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