import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'database_service.dart';

ValueNotifier<AuthService> authService = ValueNotifier(AuthService());

class AuthService{
  final FirebaseAuth firebaseAuth = FirebaseAuth.instance;
  final DatabaseService databaseService = DatabaseService();
  User? get currentUser => firebaseAuth.currentUser;
  Stream<User?> get authStateChanges => firebaseAuth.authStateChanges();

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async{
    return await firebaseAuth.signInWithEmailAndPassword(
        email: email, password: password);
  }

  Future<UserCredential> createAccount({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential userCredential = await firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Extract and format name from email
      String formattedName = email
          .split('@')[0]                // Get part before @
          .split('.')                   // Split into name components
          .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
          .join(' ');                   // Capitalize and join with spaces

      final userData = {
        'email': email,
        'name': formattedName,
        'createdAt': ServerValue.timestamp,
      };
      final Map<String, dynamic> userInfo = {
        'users/${userCredential.user!.uid}': userData,
        'Attendance_Record/Internet/${userCredential.user!.uid}/info': userData,
        'Attendance_Record/Network Protocols/${userCredential.user!.uid}/info': userData,
        'Attendance_Record/Networks Lab/${userCredential.user!.uid}/info': userData,
      };

      // Fetch schedule from database
      final scheduleSnapshot = await databaseService.read(path: 'Classes');
      if (scheduleSnapshot != null && scheduleSnapshot.value != null) {
        final scheduleData = Map<String, dynamic>.from(scheduleSnapshot.value as Map);

        for (var course in scheduleData.keys) {
          Map<String, dynamic> sessions = Map<String, dynamic>.from(scheduleData[course]);
          for (var sessionId in sessions.keys) {
            var sessionData = Map<String, dynamic>.from(sessions[sessionId]);

            userInfo['Attendance_Record/$course/${userCredential.user!.uid}/sessions/$sessionId'] = {
              'state': 'absent',
              'start': sessionData['start'],
              'end': sessionData['end'],
            };
          }
        }
      }

      // Save all in one atomic write
      await databaseService.multiCreate(userInfo);
      return userCredential;
    } catch (e) {
      throw Exception('Account creation failed: ${e.toString()}');
    }
  }

  Future<void> signOut() async{
    await firebaseAuth.signOut();
  }
  Future<void> resetPassword(String text, {
    required String email,
  }) async {
    await firebaseAuth.sendPasswordResetEmail(email: email);
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();

      if (googleUser == null) {
        throw Exception('Google sign-in was cancelled');
      }

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential =
      await firebaseAuth.signInWithCredential(credential);

      // For new users, create entries in multiple paths
      if (userCredential.additionalUserInfo?.isNewUser ?? false) {
        final user = userCredential.user!;
        final uid = user.uid;

        final userData = {
          'email': user.email,
          'name': user.displayName,
          'createdAt': ServerValue.timestamp,
        };

        final userInfo = {
          'users/$uid': userData,
          'Attendance_Record/Internet/$uid/info': userData,
          'Attendance_Record/Network Protocols/$uid/info': userData,
          'Attendance_Record/Networks Lab/$uid/info': userData,
        };

        final scheduleSnapshot = await databaseService.read(path: 'Classes');
        if (scheduleSnapshot != null && scheduleSnapshot.value != null) {
          final scheduleData = Map<String, dynamic>.from(scheduleSnapshot.value as Map);

          for (var course in scheduleData.keys) {
            Map<String, dynamic> sessions = Map<String, dynamic>.from(scheduleData[course]);
            for (var sessionId in sessions.keys) {
              var sessionData = Map<String, dynamic>.from(sessions[sessionId]);

              userInfo['Attendance_Record/$course/$uid/sessions/$sessionId'] = {
                'state': 'absent',
                'start': sessionData['start'],
                'end': sessionData['end'],
              };
            }
          }
        }

        // Use multiCreate for atomic writes
        await databaseService.multiCreate(userInfo);
      }
      return userCredential;
    } catch (e) {
      throw Exception('Google sign-in failed: ${e.toString()}');
    }
  }
}