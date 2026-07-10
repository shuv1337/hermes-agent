# R8 full mode (AGP 8 default) strips the no-arg constructor of Room's
# generated databases, crashing androidx.startup's WorkManager init with
# NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init> [].
# Keep Room database implementations constructible.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
