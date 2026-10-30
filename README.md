SocialEats

NIBM iOS Application Development (BSCCOMP25.1P) — Final Coursework

App overview

SocialEats helps people who eat alone find company for a meal. Nearby restaurant tables become small open meetups that anyone can join.

See open tables near you on a live feed and map.
Join a table with Face ID / Touch ID and get an offline QR pass.
Chat with your table group.
Scan your receipt after the meal (on device Vision AI) to earn Foodie Karma.
Shake your phone to instantly match with a nearby table.
Host your own table.

Built with SwiftUI (MVVM), Firebase, Core Data, Vision, Core Motion and MapKit. Works on iPhone and iPad.

How markers can reach the backend -

The backend is Firebase (Authentication + Cloud Firestore). GoogleService-Info.plist is included, so the app connects automatically.

Test account (no real SMS needed). On the sign in screen, under Direct Mobile Access:

Country: Sri Lanka (+94)
Phone number: xx xxx xxxx
Code: xxxxxx

Read only access: the lecturer has been added to the Firebase project as a Viewer. Open https://console.firebase.google.com → SocialEats project → Authentication and Firestore Database.

Fresh demo tables: in the app, go to Settings → Add sample tables near me.

How to run -
Open SocialEats.xcodeproj in Xcode 26 or later.
Choose an iPhone or iPad simulator and press Cmd + R.
Sign in with the test account above.
Press Cmd + U to run the unit tests.
