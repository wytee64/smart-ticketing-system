import ballerina/io;
import ballerina/log;
import ballerina/time;
import ballerinax/kafka;
import ballerinax/mongodb;
import ballerina/regex;

// === KAFKA CONFIGURATION ===//
configurable string kafkaBootstrapServers = "localhost:9092";

// Kafka Producer for sending schedule updates
kafka:ProducerConfiguration producerConfig = {
    clientId: "transport-service-producer",
    acks: "all",
    retryCount: 3
};

kafka:Producer scheduleProducer = check new (kafkaBootstrapServers, producerConfig);

// Kafka Consumer for receiving ticket purchases
kafka:ConsumerConfiguration consumerConfig = {
    groupId: "transport-service-group",
    offsetReset: "earliest",
    topics: ["ticket.purchased"]
};

kafka:Consumer transportConsumer = check new (kafkaBootstrapServers, consumerConfig);

// === MONGODB CONFIGURATION ===
configurable string mongoUrl = "mongodb://wytee:cookingdsa@localhost:27017";
configurable string databaseName = "transport_db";

mongodb:Client mongoClient = check new ({
    connection: mongoUrl
});

// === DATA TYPES ===
type ScheduleUpdate record {|
    string updateId?;
    string tripId;
    string updateType;
    string message;
    string timestamp;
    int? delayMinutes?;
|};

type TicketPurchasedEvent record {|
    string ticketId;
    string passengerId;
    string tripId;
    string ticketType;
    decimal amount;
    string purchasedAt;
|};

// === MAIN APPLICATION ===
public function main() returns error? {
    io:println("=== SMART PUBLIC TRANSPORT SYSTEM ===");
    io:println("=== TRANSPORT SERVICE (TERMINAL MODE) ===");
    
    // Start Kafka consumer in background
    _ = start kafkaConsumerWorker();
    
    // Main menu loop
    while true {
        printMainMenu();
        string choice = io:readln("Choose an option (1-6): ");
        
        match choice {
            "1" => { _ = check createNewRoute(); }
            "2" => { _ = check createNewTrip(); }
            "3" => { _ = check viewAllRoutes(); }
            "4" => { _ = check viewTripsForRoute(); }
            "5" => { _ = check updateTripStatus(); }
            "6" => { 
                io:println("Exiting Transport Service...");
                break; 
            }
            _ => { io:println("Invalid option! Please try again."); }
        }
    }
}

// === KAFKA CONSUMER WORKER ===
function kafkaConsumerWorker() returns error? {
    io:println("Starting Kafka Consumer for ticket.purchased topic...");
    
    while true {
        kafka:ConsumerRecord[] records = check transportConsumer->poll(1000);
        
        foreach var kafkaRecord in records {
            handleTicketPurchased(kafkaRecord);
            
            // Commit offset after processing
            check transportConsumer->commit();
        }
    }
}

function handleTicketPurchased(kafka:ConsumerRecord kafkaRecord) {
    io:println("\n🎫 RECEIVED TICKET PURCHASE NOTIFICATION:");
    
    // Parse the ticket purchased event from byte array
    byte[] messageBytes = kafkaRecord.value;
    string|error messageStr = string:fromBytes(messageBytes);
    
    if messageStr is error {
        log:printError("Failed to parse message", messageStr);
        return;
    }
    
    json|error payload = messageStr.fromJsonString();
    if payload is error {
        log:printError("Failed to parse JSON", payload);
        return;
    }
    
    TicketPurchasedEvent|error ticketEvent = payload.cloneWithType(TicketPurchasedEvent);
    if ticketEvent is error {
        log:printError("Failed to convert to TicketPurchasedEvent", ticketEvent);
        return;
    }
    
    io:println("   Ticket ID: " + ticketEvent.ticketId);
    io:println("   Trip ID: " + ticketEvent.tripId);
    io:println("   Passenger: " + ticketEvent.passengerId);
    io:println("   Amount: N$" + ticketEvent.amount.toString());
    
    // Update available seats for the trip
    error? result = updateTripSeats(ticketEvent.tripId, -1);
    if result is error {
        log:printError("Failed to update trip seats", result);
    }
}

// === KAFKA PRODUCER FUNCTIONS ===
function publishScheduleUpdate(ScheduleUpdate update) returns error? {
    update.updateId = "UPDATE_" + time:utcNow()[0].toString();
    update.timestamp = time:utcToString(time:utcNow());
    
    _ = check scheduleProducer->send({
        topic: "schedule.updates",
        value: update.toJsonString(),
        key: update.tripId
    });
    
    io:println("📢 Published schedule update to Kafka:");
    io:println("   Topic: schedule.updates");
    io:println("   Trip: " + update.tripId);
    io:println("   Update: " + update.updateType);
    io:println("   Message: " + update.message);
}

// === MENU FUNCTIONS ===
function printMainMenu() {
    io:println("\n📋 MAIN MENU:");
    io:println("1. Create New Route");
    io:println("2. Create New Trip");
    io:println("3. View All Routes");
    io:println("4. View Trips for Route");
    io:println("5. Update Trip Status");
    io:println("6. Exit");
}

function createNewRoute() returns error? {
    io:println("\n🛣️ CREATE NEW ROUTE");
    
    string routeName = io:readln("Route Name: ");
    string routeType = io:readln("Route Type (BUS/TRAIN): ");
    string startLocation = io:readln("Start Location: ");
    string endLocation = io:readln("End Location: ");
    string stopsInput = io:readln("Stops (comma-separated): ");
    string distanceInput = io:readln("Distance (km): ");
    string baseFareInput = io:readln("Base Fare: ");

    // Parse decimal values with error handling
    decimal|error distance = decimal:fromString(distanceInput);
    if distance is error {
        return error("Invalid distance: " + distanceInput);
    }
    
    decimal|error baseFare = decimal:fromString(baseFareInput);
    if baseFare is error {
        return error("Invalid base fare: " + baseFareInput);
    }
    
    string[] stops = regex:split(stopsInput, ","); 
       
    mongodb:Database database = check mongoClient->getDatabase(databaseName);
    mongodb:Collection routesCollection = check database->getCollection("routes");
    
    map<json> newRoute = {
        "routeName": routeName,
        "routeType": routeType,
        "startLocation": startLocation,
        "endLocation": endLocation,
        "stops": stops,
        "distance": distance,
        "baseFare": baseFare,
        "status": "ACTIVE",
        "createdAt": time:utcToString(time:utcNow())
    };
    
    check routesCollection->insertOne(newRoute);
    
    io:println("✅ Route created successfully!");
}

function createNewTrip() returns error? {
    io:println("\n🚌 CREATE NEW TRIP");
    
    string routeId = io:readln("Route ID: ");
    string vehicleId = io:readln("Vehicle ID: ");
    string departureTime = io:readln("Departure Time (YYYY-MM-DD HH:MM): ");
    string arrivalTime = io:readln("Arrival Time (YYYY-MM-DD HH:MM): ");
    string totalSeatsInput = io:readln("Total Seats: ");
    string driverId = io:readln("Driver ID (optional): ");

    // Parse integer with error handling
    int|error totalSeats = int:fromString(totalSeatsInput);
    if totalSeats is error {
        return error("Invalid total seats: " + totalSeatsInput);
    }
    
    mongodb:Database database = check mongoClient->getDatabase(databaseName);
    mongodb:Collection tripsCollection = check database->getCollection("trips");
    
    map<json> newTrip = {
        "routeId": routeId,
        "vehicleId": vehicleId,
        "scheduledDeparture": departureTime,
        "scheduledArrival": arrivalTime,
        "status": "SCHEDULED",
        "availableSeats": totalSeats,
        "totalSeats": totalSeats,
        "driverId": driverId,
        "createdAt": time:utcToString(time:utcNow())
    };
    
    check tripsCollection->insertOne(newTrip);
    
    io:println("✅ Trip created successfully!");
}

function viewAllRoutes() returns error? {
    io:println("\n📄 ALL ACTIVE ROUTES:");
    
    mongodb:Database database = check mongoClient->getDatabase(databaseName);
    mongodb:Collection routesCollection = check database->getCollection("routes");
    
    stream<record {}, error?> routeStream = check routesCollection->find({"status": "ACTIVE"});
    
    int count = 0;
    check from record {} route in routeStream
        do {
            count += 1;
            io:println("--- Route " + count.toString() + " ---");
            io:println("ID: " + route["_id"].toString());
            io:println("Name: " + route["routeName"].toString());
            io:println("Type: " + route["routeType"].toString());
            io:println("From: " + route["startLocation"].toString() + " → To: " + route["endLocation"].toString());
            io:println("Fare: N$" + route["baseFare"].toString());
            io:println("");
        };
    
    if count == 0 {
        io:println("No routes found.");
    }
}

function viewTripsForRoute() returns error? {
    string routeId = io:readln("Enter Route ID: ");
    
    io:println("\n🚍 TRIPS FOR ROUTE: " + routeId);
    
    mongodb:Database database = check mongoClient->getDatabase(databaseName);
    mongodb:Collection tripsCollection = check database->getCollection("trips");
    
    stream<record {}, error?> tripStream = check tripsCollection->find({"routeId": routeId});
    
    int count = 0;
    check from record {} trip in tripStream
        do {
            count += 1;
            io:println("--- Trip " + count.toString() + " ---");
            io:println("Trip ID: " + trip["_id"].toString());
            io:println("Vehicle: " + trip["vehicleId"].toString());
            io:println("Departure: " + trip["scheduledDeparture"].toString());
            io:println("Arrival: " + trip["scheduledArrival"].toString());
            io:println("Status: " + trip["status"].toString());
            io:println("Seats: " + trip["availableSeats"].toString() + "/" + trip["totalSeats"].toString());
            io:println("");
        };
    
    if count == 0 {
        io:println("No trips found for this route.");
    }
}

function updateTripStatus() returns error? {
    io:println("\n🔄 UPDATE TRIP STATUS");
    
    string tripId = io:readln("Trip ID: ");
    io:println("Status Options: DELAYED, CANCELLED, DEPARTED, ARRIVED");
    string newStatus = io:readln("New Status: ");
    string reason = io:readln("Reason: ");
    
    int? delayMinutes = ();
    if newStatus == "DELAYED" {
        string delayInput = io:readln("Delay (minutes): ");
        int|error delay = int:fromString(delayInput);
        if delay is error {
            return error("Invalid delay minutes: " + delayInput);
        }
        delayMinutes = delay;
    }
    
    mongodb:Database database = check mongoClient->getDatabase(databaseName);
    mongodb:Collection tripsCollection = check database->getCollection("trips");
    
    // Update in database
    mongodb:UpdateResult updateResult = check tripsCollection->updateOne(
        {"_id": tripId},
        {"$set": {"status": newStatus}}
    );
    
    if updateResult.modifiedCount > 0 {
        // Publish schedule update
        ScheduleUpdate update = {
            tripId: tripId,
            updateType: newStatus,
            message: reason,
            delayMinutes: delayMinutes,
            timestamp: ""
        };
        
        _ = check publishScheduleUpdate(update);
        io:println("✅ Trip status updated and notification sent!");
    } else {
        io:println("❌ Trip not found!");
    }
}

function updateTripSeats(string tripId, int seatChange) returns error? {
    mongodb:Database database = check mongoClient->getDatabase(databaseName);
    mongodb:Collection tripsCollection = check database->getCollection("trips");
    
    // Get current trip
    map<json>? existingTrip = check tripsCollection->findOne({"_id": tripId});
    
    if existingTrip is map<json> {
        int currentSeats = <int>existingTrip["availableSeats"];
        int newSeats = currentSeats + seatChange;
        if newSeats < 0 { 
            newSeats = 0; 
        }
        
        // Update seats
        mongodb:UpdateResult _ = check tripsCollection->updateOne(
            {"_id": tripId},
            {"$set": {"availableSeats": newSeats}}
        );
        
        io:println("   Updated seats for trip " + tripId + ": " + newSeats.toString() + " available");
        
        // Notify if seats are running low
        if newSeats <= 5 {
            ScheduleUpdate seatUpdate = {
                tripId: tripId,
                updateType: "SEAT_ALERT",
                message: "Only " + newSeats.toString() + " seats remaining!",
                timestamp: ""
            };
            _ = check publishScheduleUpdate(seatUpdate);
        }
    }
}