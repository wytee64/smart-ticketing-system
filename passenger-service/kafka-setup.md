# steps

## step 1: start kafka
- .\bin\windows\kafka-server-start.bat .\config\server.properties

## step 2: open new terminal in kafka folder

## step 3: cd into the windows folder 
- cd bin\windows

## step 4 : run the commands to create prod and cons
- kafka-topics.bat --create --topic passenger_events --bootstrap-server localhost:9092
- kafka-topics.bat --create --topic ticket_events --bootstrap-server localhost:9092

## check if they exist
- kafka-topics.bat --list --bootstrap-server localhost:9092
