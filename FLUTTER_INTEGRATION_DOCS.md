# Flutter Frontend Integration Documentation

This document outlines everything that has been implemented in the Flutter application to connect it to the FastAPI backend. It serves as a guide for team members to understand the current architecture, what has been done, and how the API integration works step by step.

---

## 1. Overview
The UI was pre-built, but it was completely offline. We have successfully implemented a fully functional API layer connecting the Flutter frontend to the FastAPI backend. 

The integration was carried out in **5 structured phases**, ensuring that the existing UI design and navigation flow remained intact while injecting live data capabilities.

---

## 2. Phase 1: API Foundation Layer
**Goal:** Create a centralized configuration and service layer for all HTTP requests without modifying any existing UI code.
*   **Files Created:**
    *   `lib/config/api.dart`: Holds the core configuration, such as the `baseUrl` (`http://10.0.2.2:8000` for Android emulator local testing).
    *   `lib/services/api_service.dart`: The main networking class (`ApiService`). 
*   **How it works:**
    *   It maintains a static `token` variable.
    *   It provides a `getHeaders()` method that automatically injects the `Content-Type: application/json` and `Authorization: Bearer <token>` headers into every subsequent request if the user is authenticated.
    *   It contains all the API methods (`login`, `getMeals`, `createBooking`, `getQrData`) returning cleanly decoded JSON maps or lists.

---

## 3. Phase 2: Login Integration
**Goal:** Connect the login screen to the backend authentication system.
*   **File Modified:** `lib/login_screen.dart`
*   **What was done:**
    *   Modified the `_handleLogin()` function attached to the "Enter the Mess" button.
    *   It now collects the `identifier` (Email or UID) and `password`.
    *   Calls `ApiService.login(identifier, password)`.
    *   If the backend returns HTTP 200, the `access_token` is automatically extracted and saved in the `ApiService` via `setToken()`.
    *   If the login fails, it safely catches the exception and displays the exact backend error message using a red `SnackBar`.
    *   Upon success, the user is navigated to the `/home` route.

---

## 4. Phase 3: Meals Slots Integration
**Goal:** Fetch dynamic meal slots from the backend and display them on the Home Dashboard.
*   **File Modified:** `lib/home_screen.dart`
*   **What was done:**
    *   Added state variables: `List<dynamic> _meals`, `bool _isLoadingMeals`, and `String? _mealsError`.
    *   Added a new `_fetchMeals()` asynchronous method that is triggered immediately inside the widget's `initState()`.
    *   This method calls `ApiService.getMeals()` (hitting `GET /api/meals/slots`).
    *   Added a new UI component `_buildMealsList()` directly below the Active Booking card.
    *   This component gracefully handles loading spinners, error text, and ultimately uses a `ListView.builder` to dynamically render the `name`, `start_time`, and `end_time` of every available meal slot received from the backend.

---

## 5. Phase 4: Booking System
**Goal:** Allow users to submit meal bookings to the database.
*   **File Modified:** `lib/meal_booking_screen.dart`
*   **What was done:**
    *   Updated the `_confirmBooking(int index)` method attached to the confirmation flow.
    *   Added front-end validation to ensure `selected.isEmpty` is caught (requiring at least one item).
    *   Constructs the payload: `slotId` (derived from the selected tab), `dateStr` (formatted to `YYYY-MM-DD`), and `itemIds` (a list of integers representing the chosen menu items).
    *   Calls `ApiService.createBooking()`.
    *   If it fails (HTTP 400+), the UI halts, decodes the specific FastAPI error (`response.body['detail']`), and shows a `SnackBar` warning.
    *   If successful, it shows a green confirmation `SnackBar` and seamlessly falls back into the existing local navigation logic so the user proceeds to the Meal Pass screen without breaking the UI flow.

---

## 6. Phase 5: QR System
**Goal:** Fetch secure, encrypted QR data from the backend to display on the digital meal pass.
*   **File Modified:** `lib/meal_pass_screen.dart`
*   **What was done:**
    *   Added a new `GET /api/tokens/qr-data/{booking_id}` method to `ApiService`.
    *   In the Meal Pass screen, added `_fetchQrData()` called within `initState()`.
    *   It extracts the active booking ID from the local `orderID` data, hits the API, and retrieves the secure `qr_payload` string.
    *   Updated the `QrImageView` widget inside `_buildPassCard()` to conditionally render a `CircularProgressIndicator` while the payload is fetching.
    *   Once fetched, the QR code is generated using the real backend payload (`_qrPayload`) instead of a mocked string, ensuring the pass can be legitimately scanned by the staff system.

---

### Conclusion
The frontend UI is now fully interconnected with the backend API. The underlying local data structure was mostly preserved so the app's visual state did not break, but all critical data events (Login, Fetching Meals, Booking Meals, and fetching QR tokens) are now live network requests.
