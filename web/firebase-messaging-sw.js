importScripts("https://www.gstatic.com/firebasejs/9.22.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.22.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyC_oNfk5yizWgVImuR5bYN9YBK1T0mbYvE",
  appId: "1:977867086170:web:1af3d7bd4246d2225e3b63",
  messagingSenderId: "977867086170",
  projectId: "unihub-5d151",
  storageBucket: "unihub-5d151.firebasestorage.app",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function (payload) {
  console.log("[firebase-messaging-sw.js] Received background message ", payload);
  const notificationTitle = payload.notification ? payload.notification.title : (payload.data ? payload.data.title : "UniHub Notice");
  const notificationOptions = {
    body: payload.notification ? payload.notification.body : (payload.data ? payload.data.body : ""),
    icon: "/icons/Icon-192.png",
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
