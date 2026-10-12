import Foundation

public enum UpdateRelaunchGate {
    public static func mayRelaunch(idle: Bool, deliveringTranscript: Bool, inserting: Bool) -> Bool {
        idle && !deliveringTranscript && !inserting
    }
}
