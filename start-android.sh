# Kill Stucked Proess
PID=$(lsof -tiTCP:8080 -sTCP:LISTEN); if [ -n "$PID" ]; then kill $PID && echo "Stopped process(es): $PID"; else echo "No process found on port 8080"; fi

# Restart the backend:
cd "/Users/andrewstardie/Documents/TUTS/TESTS/ynk/YɛnKɔ/backend" && clear;clear && npm run start:local

#Start Flutter (Front-End)
cd "/Users/andrewstardie/Documents/TUTS/TESTS/ynk/YɛnKɔ" && clear;clear && flutter run -d emulator-5554 --dart-define=YENKO_USE_LOCAL_API=true --dart-define=YENKO_API_BASE_URL=http://10.0.2.2:8080

 
# Build APK
cd "/Users/andrewstardie/Documents/TUTS/TESTS/YɛnKɔ"  && clear;clear && flutter build apk --debug --dart-define=YENKO_USE_LOCAL_API=true --dart-define=YENKO_API_BASE_URL=http://10.0.2.2:8080




