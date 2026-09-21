pragma Singleton
import Quickshell
Singleton { readonly property string notificationsPath: Quickshell.env("TEST_HISTORY") }
