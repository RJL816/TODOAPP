package com.example.todo_app

/** Independent from the pomodoro service and its end alarm. */
class WorkoutOverlayService : FocusOverlayService() {
    override val training = true
}
