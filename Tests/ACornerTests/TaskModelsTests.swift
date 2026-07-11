import Foundation
import Testing
@testable import ACorner

@Test("任务记录可稳定编码与解码")
func taskRecordRoundTrip() throws {
    let record = TaskRecord(
        id: UUID(),
        title: "整理开发说明",
        plannedMinutes: 25,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        plannedEndsAt: Date(timeIntervalSince1970: 1_700_001_500),
        completedAt: Date(timeIntervalSince1970: 1_700_001_800),
        actualDuration: 1_800,
        continuedAfterPlan: true,
        additionalDuration: 300,
        note: "补充了测试文档。",
        finishKind: .completed
    )

    let data = try JSONEncoder().encode(record)
    let restored = try JSONDecoder().decode(TaskRecord.self, from: data)

    #expect(restored == record)
}
