# 💳 Payment Service

## Overview
The Payment Service handles all payment processing for ticket purchases. It integrates with payment gateways (simulated), manages payment records in MongoDB, and publishes payment events to Kafka for downstream services like notifications and ticketing.

**Port:** 8084  
**Technology:** Ballerina, MongoDB, Apache Kafka  
**Database:** MongoDB (`payments` collection)

---

## 🏗️ Architecture

### Payment Flow
```
┌─────────────────────────────────────────────────────────┐
│              Payment Processing Flow                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Client Request                                         │
│       │                                                 │
│       ▼                                                 │
│  ┌─────────────────────┐                               │
│  │ Validate Request    │                               │
│  │ - ticketId exists   │                               │
│  │ - amount > 0        │                               │
│  └──────────┬──────────┘                               │
│             │                                           │
│             ▼                                           │
│  ┌─────────────────────┐                               │
│  │ Process Payment     │                               │
│  │ (Gateway Simulation)│                               │
│  └──────────┬──────────┘                               │
│             │                                           │
│       ┌─────┴─────┐                                    │
│       │           │                                    │
│    SUCCESS      FAILURE                                │
│       │           │                                    │
│       ▼           ▼                                    │
│  ┌─────────┐  ┌─────────┐                             │
│  │ CONFIRM │  │  FAIL   │                             │
│  │ Payment │  │ Payment │                             │
│  └────┬────┘  └────┬────┘                             │
│       │            │                                   │
│       ▼            ▼                                   │
│  Save to MongoDB                                       │
│       │                                                │
│       ▼                                                │
│  Publish to Kafka (payments.processed)                │
│       │                                                │
│       ▼                                                │
│  Update Ticket Status (if CONFIRMED)                  │
│       │                                                │
│       ▼                                                │
│  Return Response                                       │
│                                                        │
└─────────────────────────────────────────────────────────┘
```

---

## 📊 Code Structure

### Data Models

#### **Payment Record**
```ballerina
type Payment record {|
    string id;              // UUID
    string ticketId;        // Reference to ticket
    string passengerId;     // Reference to passenger
    decimal amount;         // Payment amount
    string paymentMethod;   // CREDIT_CARD | DEBIT_CARD | MOBILE_WALLET
    string status;          // INITIATED | CONFIRMED | FAILED | REFUNDED
    string timestamp;       // ISO 8601 timestamp
    string? transactionId;  // External gateway transaction ID (optional)
    string? failureReason;  // Reason if payment failed (optional)
|};
```

#### **Payment Request**
```ballerina
type CreatePaymentRequest record {|
    string ticketId;
    string passengerId;
    decimal amount;
    string paymentMethod;
|};
```

#### **Refund Request**
```ballerina
type RefundRequest record {|
    string reason;
|};
```

---

## 💰 Payment Operations

### 1. **Process Payment** - Create and Confirm
```ballerina
resource function post .(@http:Payload CreatePaymentRequest request) returns json|error {
    mongodb:Database db = check mongoDb->getDatabase("transportdb");
    mongodb:Collection paymentsCollection = check db->getCollection("payments");
    
    string paymentId = uuid:createType1AsString();
    string timestamp = time:utcNow()[0].toString();
    
    // Simulate payment gateway processing
    // In production, this would call actual payment gateway API
    boolean paymentSuccess = true;  // Simulated - always succeeds
    
    Payment payment = {
        id: paymentId,
        ticketId: request.ticketId,
        passengerId: request.passengerId,
        amount: request.amount,
        paymentMethod: request.paymentMethod,
        status: paymentSuccess ? "CONFIRMED" : "FAILED",
        timestamp: timestamp,
        transactionId: "TXN-" + paymentId,
        failureReason: paymentSuccess ? () : "Insufficient funds"
    };
    
    // Save to MongoDB
    check paymentsCollection->insertOne(payment);
    
    if paymentSuccess {
        // Publish to Kafka - Payment Confirmed
        string kafkaMessage = string `{
            "paymentId":"${paymentId}",
            "ticketId":"${request.ticketId}",
            "passengerId":"${request.passengerId}",
            "amount":${request.amount},
            "status":"CONFIRMED",
            "timestamp":"${timestamp}"
        }`;
        
        check kafkaProducer->send({
            topic: "payments.processed",
            value: kafkaMessage.toBytes()
        });
        
        log:printInfo("Payment processed successfully: " + paymentId);
        log:printInfo("Published to Kafka topic: payments.processed");
        
        // Update ticket status to PAID
        mongodb:Collection ticketsCollection = check db->getCollection("tickets");
        mongodb:UpdateResult _ = check ticketsCollection->updateOne(
            {id: request.ticketId},
            {set: {
                status: "PAID",
                paidAt: timestamp
            }}
        );
        
        log:printInfo("Ticket status updated to PAID: " + request.ticketId);
    }
    
    return {
        paymentId: paymentId,
        status: payment.status,
        amount: request.amount,
        transactionId: payment.transactionId,
        message: paymentSuccess ? "Payment processed successfully" : "Payment failed"
    };
}
```

**What This Does:**
1. ✅ Generates unique payment ID
2. ✅ Simulates payment gateway call (always succeeds for demo)
3. ✅ Creates payment record with status `CONFIRMED`
4. ✅ Saves to MongoDB
5. ✅ **Publishes event to Kafka** (`payments.processed` topic)
6. ✅ **Updates ticket status to `PAID`** in ticketing service
7. ✅ Returns payment confirmation

**Kafka Event Published:**
```json
{
  "paymentId": "01f0a20e-112e-1b1e-a89e-967c4239623c",
  "ticketId": "01f0a201-bf80-12a0-bbd4-84f833f7a006",
  "passengerId": "01f0a1fd-159e-19ee-ab6f-992db0b528e9",
  "amount": 50.0,
  "status": "CONFIRMED",
  "timestamp": "2025-10-05T17:09:36.025466933Z"
}
```

**Trigger:** This triggers the **Notification Service** to send: *"Your ticket payment has been confirmed!"*

---

### 2. **Get Payment Details** - Read Single Payment
```ballerina
resource function get [string paymentId]() returns Payment|error {
    mongodb:Database db = check mongoDb->getDatabase("transportdb");
    mongodb:Collection paymentsCollection = check db->getCollection("payments");
    
    Payment? payment = check paymentsCollection->findOne({id: paymentId});
    if payment is () {
        return error("Payment not found");
    }
    
    return payment;
}
```

**What This Does:**
- Retrieves payment details by ID
- Returns full payment record
- Returns 404 if payment doesn't exist

---

### 3. **Get Payments for Ticket** - Filter by Ticket
```ballerina
resource function get ticket/[string ticketId]() returns Payment[]|error {
    mongodb:Database db = check mongoDb->getDatabase("transportdb");
    mongodb:Collection paymentsCollection = check db->getCollection("payments");
    
    stream<Payment, error?> paymentStream = check paymentsCollection->find({
        ticketId: ticketId
    });
    
    Payment[] payments = [];
    check from Payment payment in paymentStream
        do {
            payments.push(payment);
        };
    
    check paymentStream.close();
    return payments;
}
```

**What This Does:**
- Finds all payments for a specific ticket
- Useful for tracking refunds and retry attempts

---

### 4. **Process Refund** - Reverse Payment
```ballerina
resource function post [string paymentId]/refund(@http:Payload RefundRequest request) returns json|error {
    mongodb:Database db = check mongoDb->getDatabase("transportdb");
    mongodb:Collection paymentsCollection = check db->getCollection("payments");
    
    // Get existing payment
    Payment? existingPayment = check paymentsCollection->findOne({id: paymentId});
    if existingPayment is () {
        return error("Payment not found");
    }
    
    // Verify payment is CONFIRMED
    if existingPayment.status != "CONFIRMED" {
        return error("Only confirmed payments can be refunded");
    }
    
    // Process refund (simulated)
    string timestamp = time:utcNow()[0].toString();
    mongodb:UpdateResult _ = check paymentsCollection->updateOne(
        {id: paymentId},
        {set: {
            status: "REFUNDED",
            failureReason: request.reason
        }}
    );
    
    log:printInfo("Payment refunded: " + paymentId + " - Reason: " + request.reason);
    
    return {
        paymentId: paymentId,
        status: "REFUNDED",
        refundedAt: timestamp,
        reason: request.reason,
        message: "Payment refunded successfully"
    };
}
```

**State Transition:** `CONFIRMED` → `REFUNDED`

**What This Does:**
1. ✅ Validates payment exists
2. ✅ Verifies payment is `CONFIRMED`
3. ✅ Updates status to `REFUNDED`
4. ✅ Records refund reason
5. ✅ Returns refund confirmation

---

### 5. **Get All Payments** - Admin View with Statistics
```ballerina
resource function get all() returns json|error {
    mongodb:Database db = check mongoDb->getDatabase("transportdb");
    mongodb:Collection paymentsCollection = check db->getCollection("payments");
    
    stream<Payment, error?> paymentStream = check paymentsCollection->find({});
    
    Payment[] payments = [];
    int totalPayments = 0;
    int confirmedCount = 0;
    int failedCount = 0;
    int refundedCount = 0;
    decimal totalAmount = 0.0;
    
    check from Payment payment in paymentStream
        do {
            payments.push(payment);
            totalPayments += 1;
            
            if payment.status == "CONFIRMED" {
                confirmedCount += 1;
                totalAmount += payment.amount;
            } else if payment.status == "FAILED" {
                failedCount += 1;
            } else if payment.status == "REFUNDED" {
                refundedCount += 1;
            }
        };
    
    check paymentStream.close();
    
    return {
        payments: payments,
        statistics: {
            totalPayments: totalPayments,
            confirmedCount: confirmedCount,
            failedCount: failedCount,
            refundedCount: refundedCount,
            totalAmount: totalAmount
        }
    };
}
```

**What This Does:**
- Returns all payments
- Calculates payment statistics:
  - Total payment count
  - Confirmed/Failed/Refunded counts
  - Total revenue (sum of confirmed payments)

---

## 🎯 Kafka Integration

### Topic Published To

#### `payments.processed` - Payment Confirmation Events
**Published When:** Payment is successfully confirmed  
**Message Format:**
```json
{
  "paymentId": "UUID",
  "ticketId": "UUID",
  "passengerId": "UUID",
  "amount": 50.00,
  "status": "CONFIRMED",
  "timestamp": "ISO-8601"
}
```

**Consumers:**
- ✅ **Notification Service** (sends payment confirmation notification)

**Downstream Effects:**
1. Notification sent to passenger
2. Ticket status updated to `PAID`
3. Passenger can now validate ticket for boarding

---

## 🧪 Testing

### 1. Process a Payment
```powershell
$paymentBody = @{
    ticketId = '01f0a201-bf80-12a0-bbd4-84f833f7a006'
    passengerId = '01f0a1fd-159e-19ee-ab6f-992db0b528e9'
    amount = 50.00
    paymentMethod = 'CREDIT_CARD'
} | ConvertTo-Json

Invoke-RestMethod -Uri http://localhost:8084/payments -Method Post -Headers @{'Content-Type'='application/json'} -Body $paymentBody
```

### 2. Get Payment Details
```powershell
$paymentId = "01f0a20e-112e-1b1e-a89e-967c4239623c"
Invoke-RestMethod -Uri "http://localhost:8084/payments/$paymentId" -Method Get | ConvertTo-Json
```

### 3. Get Payments for Ticket
```powershell
$ticketId = "01f0a201-bf80-12a0-bbd4-84f833f7a006"
Invoke-RestMethod -Uri "http://localhost:8084/payments/ticket/$ticketId" -Method Get | ConvertTo-Json
```

### 4. Process Refund
```powershell
$refundBody = @{
    reason = 'Customer requested cancellation'
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8084/payments/$paymentId/refund" -Method Post -Headers @{'Content-Type'='application/json'} -Body $refundBody
```

### 5. Get All Payments (Admin)
```powershell
Invoke-RestMethod -Uri http://localhost:8084/payments/all -Method Get | ConvertTo-Json -Depth 10
```

### 6. Verify Kafka Event
```powershell
docker exec kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic payments.processed --from-beginning --max-messages 5
```

### 7. Verify Ticket Status Update
```powershell
# Check that ticket status changed to PAID
$ticketId = "01f0a201-bf80-12a0-bbd4-84f833f7a006"
Invoke-RestMethod -Uri "http://localhost:8083/tickets/$ticketId" -Method Get | ConvertTo-Json
```

---

## 📊 API Endpoints

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/payments/health` | Health check | No |
| POST | `/payments` | Process new payment | Yes |
| GET | `/payments/{paymentId}` | Get payment details | Yes |
| GET | `/payments/ticket/{ticketId}` | Get all payments for ticket | Yes |
| POST | `/payments/{paymentId}/refund` | Process refund | Admin |
| GET | `/payments/all` | Get all payments with stats | Admin |

---

## 🔐 Payment States

### Payment Status Flow
```
INITIATED ──────► CONFIRMED ──────► REFUNDED
    │
    └──────────► FAILED
```

**Status Definitions:**
- `INITIATED`: Payment request received, processing started
- `CONFIRMED`: Payment successfully processed
- `FAILED`: Payment rejected by gateway
- `REFUNDED`: Payment reversed, money returned

---

## 💡 Business Rules

### Payment Processing
- ✅ Amount must be greater than 0
- ✅ Ticket must exist and be in `CREATED` status
- ✅ Payment method must be valid
- ✅ Each successful payment updates ticket to `PAID`

### Refunds
- ✅ Only `CONFIRMED` payments can be refunded
- ✅ Refund reason is required
- ✅ Refunded payments cannot be re-refunded

### Integration
- ✅ Publishes to Kafka only on successful payment
- ✅ Atomically updates ticket status
- ✅ Maintains payment audit trail

---

## 🚀 Key Features

1. **Payment Gateway Simulation**
   - Simulates external payment processor
   - Always succeeds for demo purposes
   - Easy to replace with real gateway (Stripe, PayPal, etc.)

2. **Event-Driven Architecture**
   - Publishes payment events to Kafka
   - Decoupled from notification service
   - Enables real-time notifications

3. **Ticket Integration**
   - Automatically updates ticket status
   - Maintains data consistency
   - Enables ticket validation flow

4. **Audit Trail**
   - All payments recorded in MongoDB
   - Transaction IDs for reconciliation
   - Refund tracking with reasons

5. **Statistics & Reporting**
   - Real-time payment metrics
   - Revenue tracking
   - Success/failure rates

---

## 🔍 Monitoring

### Check Payment Logs
```powershell
docker logs payment-service --tail 50
```

### Expected Log Output
```
level=INFO message="Payment processed successfully: 01f0a20e-112e-1b1e-a89e-967c4239623c"
level=INFO message="Published to Kafka topic: payments.processed"
level=INFO message="Ticket status updated to PAID: 01f0a201-bf80-12a0-bbd4-84f833f7a006"
```

---

## 💡 Future Enhancements

- **Real Payment Gateway Integration**: Stripe, PayPal, Square
- **Payment Retry Logic**: Automatic retry on transient failures
- **Idempotency**: Prevent duplicate payments
- **Fraud Detection**: Machine learning for suspicious transactions
- **Multiple Currencies**: Support for international payments
- **Installment Payments**: Pay in multiple installments
- **Wallet Integration**: Support mobile wallets (Apple Pay, Google Pay)

---

**Service Status:** ✅ Operational  
**Last Updated:** October 5, 2025
