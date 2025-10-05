import ballerina/http;
import ballerinax/mongodb;
import ballerina/uuid;


configurable string mongoHost = "localhost";
configurable int mongoPort = 27017;
configurable string mongoDatabase = "db";
configurable string mongoUsername = ?;
configurable string mongoPassword = ?;

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

service /passenger on new http:Listener(9010) {

    //  Register a new passenger
    //  how to call it, POST /passenger/register
    resource function post register(@http:Payload Passenger passenger) returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection passengersCollection = check db->getCollection("passengers");

        stream<Passenger, error?> existingPassengers = check passengersCollection->find({"phoneNumber": passenger.phoneNumber});
        Passenger[]|error passengers = from Passenger p in existingPassengers  // Convert stream to array
            select p;
        
        if passengers is Passenger[] && passengers.length() > 0 {
            return {
                "success": false,
                "message": "phone number already registered"    
            };
        }

        string passengerId = uuid:createType1AsString();
        passenger.passengerId = passengerId;

        check passengersCollection->insertOne(passenger);

        return {
            "success": true,
            "message": "passenger registered",
            "passengerId": passengerId
        };
    }

    //  passenger login
    //  how to call it, POST /passenger/login
    resource function post login(string emailE, string passwordE) returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection passengersCollection = check db->getCollection("passengers");

        stream<Passenger, error?> result = check passengersCollection->find({"email": emailE, "password": passwordE});
        Passenger[]|error passengers = from Passenger p in result select p;

        if passengers is Passenger[] && passengers.length() > 0 {
            Passenger p = passengers[0];
            return {
                success: true,
                message: "successful login",
                passengerId: p.passengerId
            };
        }
        return {
            success: false,
            message: "incorrect password or email",
            passengerId: ()
        };
    }

    //  Get passenger profile information
    //  how to call it, GET /passenger/profile/{passengerId}
    resource function get profile/[string passengerId]() returns Passenger|http:NotFound|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection passengersCollection = check db->getCollection("passengers");

        Passenger? passenger = check passengersCollection->findOne({"passengerId": passengerId});
        if passenger is Passenger {return passenger;}
        return http:NOT_FOUND;
    }

    //  Update passenger profile
    //  how to call it, PUT /passenger/profile/{passengerId}
    resource function put profile/[string passengerId](@http:Payload json payload) returns json|error {
        final mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection passengersCollection = check db->getCollection("passengers");

        Passenger? existingPassenger = check passengersCollection->findOne({"passengerId": passengerId});
        if existingPassenger is () {return {success: false,message: "Passenger not found"};}

        map<json> updateFields = {};
        if (payload.name != ()) {updateFields["name"] = check payload.name;}
        if (payload.phoneNumber != ()) {
            json a = check payload.phoneNumber;
            updateFields["phoneNumber"] = a;
        }

        if (updateFields.length() > 0) {
            mongodb:Update update = {"set": updateFields};
            mongodb:UpdateResult updateResult = check passengersCollection->updateOne({"passengerId": passengerId}, update);

            return {
                success: true,
                message: "profile updated",
                modifiedCount: updateResult.modifiedCount
            };
        }
        return {success: false, message: "No valid fields to update"};
    }



    //  change passenger password
    //  how to call it, PATCH /passenger/profile/{passengerId}/password
    resource function patch profile/[string passengerId]/password(@http:Payload json payload) returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection passengersCollection = check db->getCollection("passengers");
        
        string currentPassword = check payload.currentPassword;
        string newPassword = check payload.newPassword;

        Passenger? passenger = check passengersCollection->findOne({"passengerId": passengerId, "password": currentPassword});

        if passenger is () {
            return {
                success: false,
                message: "Current password is incorrect"
            };
        }

        mongodb:Update update = {"set": {"password": newPassword}};  // create update doc still
        mongodb:UpdateResult updateResult = check passengersCollection->updateOne({"passengerId": passengerId},update);
        return {
            success: true,
            message: "password changed",
            modifiedCount: updateResult.modifiedCount
        };
    }

    //  get all tickets for a passenger
    //  how to call it, GET /passenger/tickets/{passengerId}
    resource function get tickets/[string passengerId]() returns json|error {
        mongodb:Database db = check mongoDb->getDatabase(mongoDatabase);
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");

        stream<record {}, error?> result = check ticketsCollection->find({"passengerId": passengerId});
        record {}[]|error tickets = from record {} t in result select t;

        record {}[] a = check tickets;

        if tickets is record {}[] {
            json response = {
                passengerId: passengerId,
                tickets: <json>a,
                count: a.length()
            };
            return response;
        }

        return {passengerId: passengerId, tickets: [], count: 0};
    }
}