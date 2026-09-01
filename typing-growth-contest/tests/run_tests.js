/**
 * Code.gs 검증 테스트
 * 실행: node tests/run_tests.js
 *
 * Code.gs 원본을 그대로 읽어 가짜 스프레드시트 위에서 실행하므로,
 * 실제 배포되는 코드와 동일한 로직을 검사합니다.
 */

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const { createSandbox } = require("./fake-google");

const CODE_PATH = path.join(__dirname, "..", "Code.gs");
const code = fs.readFileSync(CODE_PATH, "utf8");

const EXPORTS = [
  "ADMIN_PASSWORD", "APP_TITLE", "COL", "RECORD_LAST_COL", "MAX_STROKES",
  "round1_", "pickMedianTrial_", "validateTrials_", "accuracyScore_",
  "computeResults_", "computeAwards_", "compareForRank_",
  "initializeSheets", "recalculateAll_", "readAllRecords_", "getSheet_",
  "apiGetStudents", "apiGetStudentState", "apiSaveBase", "apiSaveFinal", "apiGetMyResult",
  "apiAdminLogin", "apiAdminGetData", "apiAdminRecalculate",
  "apiAdminSaveRecord", "apiAdminDeleteRecord", "apiAdminGetCsv"
];

function loadApp() {
  const sandbox = createSandbox();
  const context = vm.createContext(sandbox.globals);
  vm.runInContext(code, context, { filename: "Code.gs" });
  vm.runInContext("globalThis.__api = { " + EXPORTS.join(", ") + " };", context);
  return { api: context.__api, spreadsheet: sandbox.spreadsheet };
}

/* ---------------- 아주 작은 테스트 도구 ---------------- */

let passed = 0;
let failed = 0;
const failures = [];

function section(title) {
  console.log("\n\x1b[1m" + title + "\x1b[0m");
}

function check(name, condition, detail) {
  if (condition) {
    passed++;
    console.log("  \x1b[32m✔\x1b[0m " + name);
  } else {
    failed++;
    failures.push(name + (detail ? "  →  " + detail : ""));
    console.log("  \x1b[31m✘ " + name + "\x1b[0m" + (detail ? "  → " + detail : ""));
  }
}

function eq(name, actual, expected) {
  check(name, actual === expected, "기대값 " + JSON.stringify(expected) + " / 실제값 " + JSON.stringify(actual));
}

function trials(a, b, c) {
  return [
    { strokes: a[0], accuracy: a[1] },
    { strokes: b[0], accuracy: b[1] },
    { strokes: c[0], accuracy: c[1] }
  ];
}

/* ============================================================
   1. 중간값(Median) 선택
   ============================================================ */
section("1. 3회 기록 중 타수의 중간값 선택");
{
  const { api } = loadApp();

  const spec = api.pickMedianTrial_(trials([184, 94], [191, 96], [176, 95]));
  eq("과제 예시(184/191/176) → 기초 타수 184", spec.strokes, 184);
  eq("중간값 회차의 정확도 94% 를 그대로 사용", spec.accuracy, 94);
  eq("선택된 회차 번호는 1회", spec.trialNo, 1);

  const desc = api.pickMedianTrial_(trials([300, 99], [200, 95], [100, 90]));
  eq("내림차순 입력(300/200/100) → 200", desc.strokes, 200);
  eq("내림차순 입력의 정확도 95%", desc.accuracy, 95);

  const asc = api.pickMedianTrial_(trials([100, 90], [200, 95], [300, 99]));
  eq("오름차순 입력(100/200/300) → 200", asc.strokes, 200);

  const tie = api.pickMedianTrial_(trials([180, 90], [180, 95], [200, 99]));
  eq("타수가 같을 때(180/180/200) → 180", tie.strokes, 180);
  eq("같은 타수 중 두 번째 기록의 정확도 95%", tie.accuracy, 95);

  const same = api.pickMedianTrial_(trials([150, 91], [150, 92], [150, 93]));
  eq("세 기록이 모두 같을 때 타수 150", same.strokes, 150);
  eq("세 기록이 모두 같을 때 정확도 92 (가운데 회차)", same.accuracy, 92);

  const notAverage = api.pickMedianTrial_(trials([100, 90], [200, 95], [900, 99]));
  eq("평균(400)이 아니라 중간값(200)을 사용", notAverage.strokes, 200);
}

/* ============================================================
   2. 입력 검증
   ============================================================ */
section("2. 입력 검증");
{
  const { api } = loadApp();

  eq("정상 입력은 통과", api.validateTrials_(trials([184, 94], [191, 96], [176, 95])).ok, true);
  eq("문자열 숫자도 통과", api.validateTrials_(trials(["184", "94"], ["191", "96"], ["176", "95"])).ok, true);
  eq("정확도 소수점 허용(94.5)", api.validateTrials_(trials([184, 94.5], [191, 96], [176, 95])).ok, true);
  eq("경계값 0타/0% 허용", api.validateTrials_(trials([0, 0], [1, 1], [2, 2])).ok, true);
  eq("경계값 1000타/100% 허용", api.validateTrials_(trials([1000, 100], [999, 99], [998, 98])).ok, true);

  const blank = api.validateTrials_(trials([184, 94], ["", 96], [176, 95]));
  eq("빈칸이 있으면 저장 불가", blank.ok, false);
  check("빈칸 안내 문구가 쉬운 말인지", /비어 있어요/.test(blank.message), blank.message);

  const overAcc = api.validateTrials_(trials([184, 120], [191, 96], [176, 95]));
  eq("정확도 120% 거부", overAcc.ok, false);
  check("정확도 안내 문구", /정확도는 0~100/.test(overAcc.message), overAcc.message);

  eq("정확도 음수 거부", api.validateTrials_(trials([184, -1], [191, 96], [176, 95])).ok, false);
  eq("타수 1001 거부", api.validateTrials_(trials([1001, 94], [191, 96], [176, 95])).ok, false);
  eq("타수 음수 거부", api.validateTrials_(trials([-5, 94], [191, 96], [176, 95])).ok, false);
  eq("타수 소수점 거부", api.validateTrials_(trials([184.5, 94], [191, 96], [176, 95])).ok, false);
  eq("숫자가 아닌 값 거부", api.validateTrials_(trials(["백팔십사", 94], [191, 96], [176, 95])).ok, false);
  eq("'184타' 같은 단위 포함 입력 거부", api.validateTrials_(trials(["184타", 94], [191, 96], [176, 95])).ok, false);
  eq("3회가 아니면 거부", api.validateTrials_([{ strokes: 1, accuracy: 1 }]).ok, false);
}

/* ============================================================
   3. 정확도 점수 (10점)
   ============================================================ */
section("3. 정확도 점수 기준");
{
  const { api } = loadApp();
  const cases = [
    [100, 10], [98, 10], [97.9, 8], [96, 8], [95.9, 6], [94, 6],
    [93.9, 4], [92, 4], [91.9, 2], [90, 2], [89.9, 0], [0, 0]
  ];
  cases.forEach(function (c) {
    eq("정확도 " + c[0] + "% → " + c[1] + "점", api.accuracyScore_(c[0]), c[1]);
  });
}

/* ============================================================
   4. 성장 계산 + 정규화 + 순위 (반 전체)
   ============================================================ */
section("4. 성장 계산 · 점수 정규화 · 순위");
{
  const { api } = loadApp();

  const klass = [
    { name: "김하늘", baseStrokes: 184, baseAccuracy: 94, finalStrokes: 247, finalAccuracy: 97 },
    { name: "이준서", baseStrokes: 300, baseAccuracy: 96, finalStrokes: 330, finalAccuracy: 98 },
    { name: "박서윤", baseStrokes: 120, baseAccuracy: 90, finalStrokes: 210, finalAccuracy: 95 },
    { name: "정민재", baseStrokes: 250, baseAccuracy: 97, finalStrokes: 250, finalAccuracy: 99 },
    { name: "최유나", baseStrokes: 200, baseAccuracy: 93, finalStrokes: 180, finalAccuracy: 91 },
    { name: "미등록", baseStrokes: 210, baseAccuracy: 92, finalStrokes: "", finalAccuracy: "" }
  ];
  const results = api.computeResults_(klass);
  const by = {};
  results.forEach(function (r) { by[r.name] = r; });

  // 증가량 / 향상률 / 정확도 변화
  eq("김하늘 증가 타수 +63", by["김하늘"].increase, 63);
  eq("김하늘 향상률 34.2% (소수점 첫째 자리)", by["김하늘"].rate, 34.2);
  eq("김하늘 정확도 변화 +3%p", by["김하늘"].accuracyDelta, 3);
  eq("최유나 증가 타수 -20", by["최유나"].increase, -20);
  eq("최유나 향상률 -10%", by["최유나"].rate, -10);
  eq("최유나 정확도 변화 -2%p", by["최유나"].accuracyDelta, -2);
  eq("정민재 증가 0타 → 향상률 0%", by["정민재"].rate, 0);

  // 정규화 (반 최고 증가량 90타 = 박서윤, 반 최고 향상률 75.0% = 박서윤)
  eq("반 최고 증가량 학생은 증가량 점수 50점", by["박서윤"].increaseScore, 50);
  eq("반 최고 향상률 학생은 향상률 점수 40점", by["박서윤"].rateScore, 40);
  eq("김하늘 증가량 점수 63/90*50 = 35", by["김하늘"].increaseScore, 35);
  eq("김하늘 향상률 점수 34.2/75*40 = 18.2", by["김하늘"].rateScore, 18.2);
  eq("이준서 증가량 점수 30/90*50 = 16.7", by["이준서"].increaseScore, 16.7);
  eq("이준서 향상률 점수 10/75*40 = 5.3", by["이준서"].rateScore, 5.3);
  eq("증가량 0 이하이면 증가량 점수 0", by["최유나"].increaseScore, 0);
  eq("향상률 0 이하이면 향상률 점수 0", by["최유나"].rateScore, 0);
  eq("증가량 0 이면 0점(정민재)", by["정민재"].increaseScore, 0);

  // 성장점수
  eq("박서윤 성장점수 50+40+6 = 96", by["박서윤"].totalScore, 96);
  eq("김하늘 성장점수 35+18.2+8 = 61.2", by["김하늘"].totalScore, 61.2);
  eq("이준서 성장점수 16.7+5.3+10 = 32", by["이준서"].totalScore, 32);
  eq("정민재 성장점수 0+0+10 = 10", by["정민재"].totalScore, 10);
  eq("최유나 성장점수 0+0+2 = 2", by["최유나"].totalScore, 2);

  // 순위
  eq("1위 박서윤", by["박서윤"].rank, 1);
  eq("2위 김하늘", by["김하늘"].rank, 2);
  eq("3위 이준서", by["이준서"].rank, 3);
  eq("4위 정민재", by["정민재"].rank, 4);
  eq("5위 최유나", by["최유나"].rank, 5);
  eq("최종 기록이 없으면 순위 없음", by["미등록"].rank, null);
  eq("최종 기록이 없으면 성장점수 없음", by["미등록"].totalScore, null);
  eq("기초 기록만 있으면 hasBase=true", by["미등록"].hasBase, true);

  // 시상
  const awards = api.computeAwards_(results);
  eq("🏆 타자 성장왕 = 박서윤", awards.growthKing.names.join(","), "박서윤");
  eq("🌱 폭풍 성장상 = 박서윤(75%)", awards.rateKing.names.join(",") + "/" + awards.rateKing.value, "박서윤/75");
  eq("🎯 정확 타자상 = 정민재(99%)", awards.accuracyKing.names.join(",") + "/" + awards.accuracyKing.value, "정민재/99");
  eq("⚡ 번개 타자상 = 이준서(330타)", awards.speedKing.names.join(",") + "/" + awards.speedKing.value, "이준서/330");
}

/* ============================================================
   5. 점수 상한 · 0 나누기 · 예외 상황
   ============================================================ */
section("5. 점수 상한 · 0으로 나누기 · 예외 상황");
{
  const { api } = loadApp();

  // 증가량·향상률 모두 1등이면서 정확도 98% 이상 → 정확히 100점
  const top = api.computeResults_([
    { name: "만점", baseStrokes: 100, baseAccuracy: 90, finalStrokes: 300, finalAccuracy: 99 },
    { name: "보통", baseStrokes: 200, baseAccuracy: 95, finalStrokes: 210, finalAccuracy: 96 }
  ]);
  eq("최고 성장 학생의 성장점수는 정확히 100점", top[0].totalScore, 100);
  check("성장점수가 100점을 넘지 않음", top.every(function (r) { return r.totalScore === null || r.totalScore <= 100; }));

  // 기초 타수 0 → 0으로 나누기 방지
  const zero = api.computeResults_([
    { name: "0타", baseStrokes: 0, baseAccuracy: 80, finalStrokes: 150, finalAccuracy: 95 }
  ]);
  eq("기초 타수 0일 때 향상률 0 (NaN/Infinity 아님)", zero[0].rate, 0);
  check("기초 타수 0일 때 성장점수가 숫자", isFinite(zero[0].totalScore), String(zero[0].totalScore));
  eq("기초 타수 0이어도 증가량 점수는 계산됨", zero[0].increaseScore, 50);

  // 아무도 성장하지 않은 반 → 모두 0점 (0으로 나누기 방지)
  const none = api.computeResults_([
    { name: "A", baseStrokes: 200, baseAccuracy: 95, finalStrokes: 180, finalAccuracy: 95 },
    { name: "B", baseStrokes: 200, baseAccuracy: 95, finalStrokes: 200, finalAccuracy: 95 }
  ]);
  eq("아무도 성장하지 않으면 증가량 점수 0", none[0].increaseScore, 0);
  eq("아무도 성장하지 않으면 향상률 점수 0", none[1].rateScore, 0);
  check("이때도 점수가 NaN 이 아님", none.every(function (r) { return isFinite(r.totalScore); }));

  // 기록이 하나도 없을 때
  const empty = api.computeResults_([]);
  eq("빈 명단이면 결과도 빈 배열", empty.length, 0);
  const emptyAwards = api.computeAwards_([]);
  eq("기록이 없으면 시상자도 없음", emptyAwards.growthKing.names.length, 0);

  // 학생 한 명뿐일 때 → 정규화 기준이 자기 자신
  const solo = api.computeResults_([
    { name: "혼자", baseStrokes: 100, baseAccuracy: 90, finalStrokes: 120, finalAccuracy: 93 }
  ]);
  eq("학생이 한 명이면 증가량 점수 50점", solo[0].increaseScore, 50);
  eq("학생이 한 명이면 향상률 점수 40점", solo[0].rateScore, 40);
  eq("학생이 한 명일 때 성장점수 50+40+4", solo[0].totalScore, 94);
}

/* ============================================================
   6. 동점 처리 규칙
   ============================================================ */
section("6. 동점자 순위 규칙 (정확도 → 증가량 → 향상률)");
{
  const { api } = loadApp();

  // 같은 성장점수(정규화 기준을 만들 학생 포함) → 최종 정확도가 높은 학생이 앞
  const tie = api.computeResults_([
    { name: "기준", baseStrokes: 100, baseAccuracy: 90, finalStrokes: 300, finalAccuracy: 90 },
    { name: "가", baseStrokes: 200, baseAccuracy: 90, finalStrokes: 260, finalAccuracy: 96 },
    { name: "나", baseStrokes: 200, baseAccuracy: 90, finalStrokes: 260, finalAccuracy: 97 }
  ]);
  const byName = {};
  tie.forEach(function (r) { byName[r.name] = r; });
  eq("두 학생의 성장점수가 같음", byName["가"].totalScore, byName["나"].totalScore);
  check("최종 정확도가 높은 '나'가 앞 순위", byName["나"].rank < byName["가"].rank,
    "나=" + byName["나"].rank + ", 가=" + byName["가"].rank);

  // 정확도까지 같고 증가량이 다른 경우
  const tie2 = api.computeResults_([
    { name: "기준", baseStrokes: 100, baseAccuracy: 90, finalStrokes: 400, finalAccuracy: 90 },
    { name: "다", baseStrokes: 100, baseAccuracy: 96, finalStrokes: 160, finalAccuracy: 96 },
    { name: "라", baseStrokes: 200, baseAccuracy: 96, finalStrokes: 320, finalAccuracy: 96 }
  ]);
  const byName2 = {};
  tie2.forEach(function (r) { byName2[r.name] = r; });
  check("향상률이 같고 증가량이 큰 '라'가 앞 순위", byName2["라"].rank < byName2["다"].rank,
    "라=" + byName2["라"].rank + "(" + byName2["라"].totalScore + "), 다=" +
    byName2["다"].rank + "(" + byName2["다"].totalScore + ")");

  // 모든 조건이 같으면 같은 순위
  const same = api.computeResults_([
    { name: "쌍둥이1", baseStrokes: 150, baseAccuracy: 95, finalStrokes: 200, finalAccuracy: 97 },
    { name: "쌍둥이2", baseStrokes: 150, baseAccuracy: 95, finalStrokes: 200, finalAccuracy: 97 }
  ]);
  eq("완전히 같은 기록이면 같은 순위(공동 1위)", same[0].rank + "," + same[1].rank, "1,1");
}

/* ============================================================
   7. 학생 화면 흐름 (시트 저장까지)
   ============================================================ */
section("7. 학생 저장 흐름 · 중복 등록 방지");
{
  const { api, spreadsheet } = loadApp();
  api.initializeSheets();

  check("initializeSheets 로 학생명단 시트 생성", !!spreadsheet.getSheetByName("학생명단"));
  check("initializeSheets 로 기록 시트 생성", !!spreadsheet.getSheetByName("기록"));

  const students = api.apiGetStudents();
  eq("샘플 학생 5명 로드", students.students.length, 5);
  eq("첫 번째 학생은 김하늘", students.students[0].name, "김하늘");

  // --- 기초 기록 저장 ---
  const base = api.apiSaveBase("김하늘", trials([184, 94], [191, 96], [176, 95]));
  eq("기초 기록 저장 성공", base.ok, true);
  eq("저장된 기초 타수 184", base.strokes, 184);
  eq("저장된 기초 정확도 94", base.accuracy, 94);

  const sheet = spreadsheet.getSheetByName("기록");
  const row = sheet.getRange(2, 1, 1, api.RECORD_LAST_COL).getValues()[0];
  eq("A열 학생명 기록", row[api.COL.NAME - 1], "김하늘");
  eq("B~G열에 3회 원본 기록 저장", [row[1], row[2], row[3], row[4], row[5], row[6]].join(","), "184,94,191,96,176,95");
  eq("H열 기초 타수 = 184", row[api.COL.BS - 1], 184);
  eq("I열 기초 정확도 = 94", row[api.COL.BA - 1], 94);
  check("Z열 마지막 수정시간 기록", String(row[api.COL.UPDATED - 1]).length > 0);

  // --- 중복 등록 방지 ---
  const dup = api.apiSaveBase("김하늘", trials([900, 99], [900, 99], [900, 99]));
  eq("기초 기록 중복 등록 거부", dup.ok, false);
  eq("중복 안내 문구", dup.message.indexOf("이미 기초 기록이 등록되어 있습니다") === 0, true);
  const rowAfter = sheet.getRange(2, 1, 1, api.RECORD_LAST_COL).getValues()[0];
  eq("중복 시도 후에도 기존 기록 유지(184)", rowAfter[api.COL.BS - 1], 184);

  // --- 최종 기록: 기초가 없으면 거부 ---
  const noBase = api.apiSaveFinal("이준서", trials([240, 97], [247, 97], [252, 98]));
  eq("기초 기록 없이 최종 기록 저장 거부", noBase.ok, false);
  check("기초 먼저 안내", /기초 기록을 먼저/.test(noBase.message), noBase.message);

  // --- 최종 기록 저장 ---
  const final = api.apiSaveFinal("김하늘", trials([240, 96], [247, 97], [252, 98]));
  eq("최종 기록 저장 성공", final.ok, true);
  eq("최종 타수도 중간값 247", final.strokes, 247);
  eq("최종 정확도는 중간값 회차의 97", final.accuracy, 97);
  eq("저장 직후 결과 상태 done", final.result.state, "done");
  eq("결과 증가 타수 +63", final.result.increase, 63);
  eq("결과 향상률 34.2%", final.result.rate, 34.2);
  eq("결과 정확도 변화 +3%p", final.result.accuracyDelta, 3);
  check("학생 결과에는 순위가 포함되지 않음", final.result.rank === undefined, JSON.stringify(final.result));

  const dupFinal = api.apiSaveFinal("김하늘", trials([900, 99], [900, 99], [900, 99]));
  eq("최종 기록 중복 등록 거부", dupFinal.ok, false);
  eq("중복 안내 문구(최종)", dupFinal.message.indexOf("이미 최종 기록이 등록되어 있습니다") === 0, true);

  // --- 상태 조회 ---
  const state = api.apiGetStudentState("김하늘");
  eq("상태 조회: 기초 등록됨", state.hasBase, true);
  eq("상태 조회: 최종 등록됨", state.hasFinal, true);
  const state2 = api.apiGetStudentState("이준서");
  eq("기록 없는 학생 상태 false", state2.hasBase || state2.hasFinal, false);

  // --- 명단에 없는 이름 ---
  const stranger = api.apiSaveBase("옆반학생", trials([100, 90], [110, 91], [120, 92]));
  eq("학생 명단에 없는 이름은 저장 거부", stranger.ok, false);
  check("명단 안내 문구", /학생 명단에 없는 이름/.test(stranger.message), stranger.message);

  // --- 다른 학생의 기록은 학생 API 로 덮어쓸 수 없음 ---
  api.apiSaveBase("이준서", trials([300, 96], [305, 97], [310, 95]));
  const overwrite = api.apiSaveBase("이준서", trials([10, 10], [10, 10], [10, 10]));
  eq("다른 학생 기록 덮어쓰기 거부", overwrite.ok, false);
  const junRow = api.readAllRecords_(sheet).filter(function (r) { return r.name === "이준서"; })[0];
  eq("이준서 기초 기록이 그대로 유지됨", junRow.baseStrokes, 305);
}

/* ============================================================
   8. 시트 재계산 (기록이 바뀌면 점수·순위 갱신)
   ============================================================ */
section("8. 기록 변경 시 전체 재계산");
{
  const { api, spreadsheet } = loadApp();
  api.initializeSheets();

  api.apiSaveBase("김하늘", trials([184, 94], [191, 96], [176, 95]));
  api.apiSaveFinal("김하늘", trials([240, 96], [247, 97], [252, 98]));
  api.apiSaveBase("이준서", trials([300, 96], [300, 96], [300, 96]));
  api.apiSaveFinal("이준서", trials([330, 98], [330, 98], [330, 98]));

  const sheet = spreadsheet.getSheetByName("기록");
  function readRow(name) {
    const rows = api.readAllRecords_(sheet);
    const found = rows.filter(function (r) { return r.name === name; })[0];
    return sheet.getRange(found.row, 1, 1, api.RECORD_LAST_COL).getValues()[0];
  }

  let hanul = readRow("김하늘");
  eq("김하늘 증가량 점수 50점 (반 최고 증가량 63타)", hanul[api.COL.INC_SCORE - 1], 50);
  eq("김하늘 향상률 점수 40점 (반 최고 향상률)", hanul[api.COL.RATE_SCORE - 1], 40);
  eq("김하늘 성장점수 98점", hanul[api.COL.TOTAL - 1], 98);
  eq("김하늘 순위 1위", hanul[api.COL.RANK - 1], 1);

  let jun = readRow("이준서");
  eq("이준서 증가량 30/63*50 = 23.8", jun[api.COL.INC_SCORE - 1], 23.8);
  eq("이준서 순위 2위", jun[api.COL.RANK - 1], 2);

  // 새 학생이 더 큰 성장을 하면 → 전체 점수/순위가 다시 계산되어야 함
  api.apiSaveBase("박서윤", trials([120, 90], [120, 90], [120, 90]));
  api.apiSaveFinal("박서윤", trials([300, 95], [300, 95], [300, 95]));

  hanul = readRow("김하늘");
  const seoyun = readRow("박서윤");
  eq("새 1등 등장 후 박서윤 증가량 점수 50점", seoyun[api.COL.INC_SCORE - 1], 50);
  eq("김하늘 증가량 점수가 63/180*50 = 17.5 로 다시 계산됨", hanul[api.COL.INC_SCORE - 1], 17.5);
  eq("박서윤 순위 1위", seoyun[api.COL.RANK - 1], 1);
  eq("김하늘 순위 2위로 변경", hanul[api.COL.RANK - 1], 2);

  const mine = api.apiGetMyResult("김하늘");
  eq("학생 결과 조회 성공", mine.ok, true);
  eq("학생 결과에도 갱신된 성장점수 반영", mine.result.increaseScore, 17.5);
  check("학생 결과에 순위 없음", mine.result.rank === undefined);

  const notYet = api.apiGetMyResult("정민재");
  eq("기록 없는 학생 결과 state=none", notYet.result.state, "none");
}

/* ============================================================
   9. 교사 관리 기능
   ============================================================ */
section("9. 교사 관리 화면 기능");
{
  const { api, spreadsheet } = loadApp();
  api.initializeSheets();

  api.apiSaveBase("김하늘", trials([184, 94], [191, 96], [176, 95]));
  api.apiSaveFinal("김하늘", trials([240, 96], [247, 97], [252, 98]));
  api.apiSaveBase("이준서", trials([300, 96], [300, 96], [300, 96]));

  eq("잘못된 비밀번호 로그인 실패", api.apiAdminLogin("0000").ok, false);
  eq("올바른 비밀번호 로그인 성공", api.apiAdminLogin(api.ADMIN_PASSWORD).ok, true);
  eq("비밀번호 없이 전체 데이터 조회 거부", api.apiAdminGetData("").ok, false);
  eq("비밀번호 없이 기록 수정 거부", api.apiAdminSaveRecord("틀림", "김하늘", { base: null, final: null }).ok, false);
  eq("비밀번호 없이 기록 삭제 거부", api.apiAdminDeleteRecord("틀림", "김하늘").ok, false);

  const data = api.apiAdminGetData(api.ADMIN_PASSWORD).data;
  eq("명단 전체(5명)가 표에 표시됨", data.rows.length, 5);
  eq("요약: 기초 기록 2명", data.summary.baseDone, 2);
  eq("요약: 최종 기록 1명", data.summary.finalDone, 1);
  eq("표 첫 줄은 기록을 마친 학생", data.rows[0].name, "김하늘");
  eq("교사 표에는 순위가 포함됨", data.rows[0].rank, 1);
  check("기록이 없는 학생도 표에 나옴", data.rows.some(function (r) { return r.name === "최유나" && !r.hasBase; }));

  // --- 기록 수정 ---
  const edit = api.apiAdminSaveRecord(api.ADMIN_PASSWORD, "김하늘", {
    base: trials([200, 90], [210, 91], [190, 92]),
    final: trials([300, 97], [310, 98], [290, 96])
  });
  eq("교사 기록 수정 성공", edit.ok, true);
  const edited = edit.data.rows.filter(function (r) { return r.name === "김하늘"; })[0];
  eq("수정 후 기초 타수 중간값 200", edited.baseStrokes, 200);
  eq("수정 후 기초 정확도 90", edited.baseAccuracy, 90);
  eq("수정 후 최종 타수 중간값 300", edited.finalStrokes, 300);
  eq("수정 후 최종 정확도 97", edited.finalAccuracy, 97);
  eq("수정 후 증가 타수 +100", edited.increase, 100);
  eq("수정 후 향상률 50%", edited.rate, 50);

  // --- 최종 기록만 지우기 ---
  const clearFinal = api.apiAdminSaveRecord(api.ADMIN_PASSWORD, "김하늘", {
    base: trials([200, 90], [210, 91], [190, 92]),
    final: trials(["", ""], ["", ""], ["", ""])
  });
  eq("최종 기록 비우기 성공", clearFinal.ok, true);
  const cleared = clearFinal.data.rows.filter(function (r) { return r.name === "김하늘"; })[0];
  eq("최종 기록이 '등록 안 함' 상태로 돌아감", cleared.hasFinal, false);
  eq("기초 기록은 유지", cleared.baseStrokes, 200);

  // --- 일부만 채우면 거부 ---
  const partial = api.apiAdminSaveRecord(api.ADMIN_PASSWORD, "김하늘", {
    base: trials([200, 90], [210, ""], [190, 92]),
    final: null
  });
  eq("일부 칸만 채우면 저장 거부", partial.ok, false);

  // --- 기초 없이 최종만 저장 거부 ---
  const onlyFinal = api.apiAdminSaveRecord(api.ADMIN_PASSWORD, "정민재", {
    base: null,
    final: trials([300, 97], [310, 98], [290, 96])
  });
  eq("기초 없이 최종만 저장 거부", onlyFinal.ok, false);

  // --- 잘못된 값 거부 ---
  const badValue = api.apiAdminSaveRecord(api.ADMIN_PASSWORD, "정민재", {
    base: trials([200, 900], [210, 91], [190, 92]),
    final: null
  });
  eq("교사 입력도 검증됨(정확도 900%)", badValue.ok, false);

  // --- 새 학생 기록 추가 ---
  const added = api.apiAdminSaveRecord(api.ADMIN_PASSWORD, "최유나", {
    base: trials([150, 92], [150, 92], [150, 92]),
    final: trials([250, 99], [250, 99], [250, 99])
  });
  eq("기록이 없던 학생도 교사가 추가 가능", added.ok, true);
  const yuna = added.data.rows.filter(function (r) { return r.name === "최유나"; })[0];
  eq("추가된 최유나 성장점수 100점(반 최고 성장)", yuna.totalScore, 100);
  eq("추가된 최유나 1위", yuna.rank, 1);

  // --- CSV ---
  const csv = api.apiAdminGetCsv(api.ADMIN_PASSWORD);
  eq("CSV 생성 성공", csv.ok, true);
  const lines = csv.csv.split("\r\n");
  eq("CSV 첫 줄은 머리글", lines[0].split(",")[0], "순위");
  eq("CSV 줄 수 = 머리글 + 학생 수", lines.length, 6);
  check("CSV 파일 이름이 .csv 로 끝남", /\.csv$/.test(csv.filename), csv.filename);
  check("CSV 에 학생 이름 포함", csv.csv.indexOf("최유나") > -1);

  // --- 삭제 ---
  const del = api.apiAdminDeleteRecord(api.ADMIN_PASSWORD, "최유나");
  eq("기록 삭제 성공", del.ok, true);
  const afterDelete = del.data.rows.filter(function (r) { return r.name === "최유나"; })[0];
  eq("삭제 후 기록 없음 상태", afterDelete.hasBase, false);
  const sheetRows = api.readAllRecords_(spreadsheet.getSheetByName("기록"));
  check("기록 시트에서도 행이 사라짐",
    !sheetRows.some(function (r) { return r.name === "최유나"; }),
    sheetRows.map(function (r) { return r.name; }).join(","));
  eq("없는 학생 삭제 시 안내", api.apiAdminDeleteRecord(api.ADMIN_PASSWORD, "없는학생").ok, false);
}

/* ============================================================
   10. 실제 학급 시나리오 (25명) – 종합 검증
   ============================================================ */
section("10. 25명 학급 시나리오 종합 검증");
{
  const { api } = loadApp();

  const klass = [];
  for (let i = 1; i <= 25; i++) {
    const base = 100 + ((i * 37) % 200);          // 100 ~ 299
    const grow = ((i * 53) % 120) - 10;           // -10 ~ 109 (성장하지 못한 학생 포함)
    const baseAcc = 88 + ((i * 7) % 10);          // 88 ~ 97
    const finalAcc = Math.min(100, baseAcc + ((i * 3) % 6));
    klass.push({
      name: "학생" + i,
      baseStrokes: base, baseAccuracy: baseAcc,
      finalStrokes: base + grow, finalAccuracy: finalAcc
    });
  }
  const results = api.computeResults_(klass);

  check("모든 학생의 성장점수가 0~100 사이", results.every(function (r) {
    return r.totalScore >= 0 && r.totalScore <= 100;
  }), JSON.stringify(results.map(function (r) { return r.totalScore; })));

  check("모든 점수가 유효한 숫자(NaN 없음)", results.every(function (r) {
    return isFinite(r.increaseScore) && isFinite(r.rateScore) && isFinite(r.accuracyScore) && isFinite(r.totalScore);
  }));

  check("증가량 점수는 50점 이하", results.every(function (r) { return r.increaseScore <= 50; }));
  check("향상률 점수는 40점 이하", results.every(function (r) { return r.rateScore <= 40; }));
  check("정확도 점수는 10점 이하", results.every(function (r) { return r.accuracyScore <= 10; }));

  const ranks = results.map(function (r) { return r.rank; }).sort(function (a, b) { return a - b; });
  eq("순위는 1부터 시작", ranks[0], 1);
  eq("순위 개수 = 학생 수", ranks.length, 25);

  const sorted = results.slice().sort(function (a, b) { return a.rank - b.rank; });
  check("순위가 성장점수 내림차순과 일치", sorted.every(function (r, i) {
    return i === 0 || sorted[i - 1].totalScore >= r.totalScore;
  }));

  check("성장점수 = 세 점수의 합", results.every(function (r) {
    return Math.abs(r.totalScore - (r.increaseScore + r.rateScore + r.accuracyScore)) < 0.051;
  }));

  const maxIncStudent = results.reduce(function (best, r) {
    return r.increase > best.increase ? r : best;
  }, results[0]);
  eq("반 최고 증가량 학생의 증가량 점수는 50점", maxIncStudent.increaseScore, 50);
}

/* ============================================================
   11. 학생 잠금 (한 번 등록하면 학생은 못 고침) · 관리 화면 진단
   ============================================================ */
section("11. 등록 후 학생 수정 차단 · 관리 화면 진단 정보");
{
  const { api, spreadsheet } = loadApp();
  api.initializeSheets();
  const sheet = spreadsheet.getSheetByName("기록");

  api.apiSaveBase("김하늘", trials([184, 94], [191, 96], [176, 95]));
  api.apiSaveFinal("김하늘", trials([240, 96], [247, 97], [252, 98]));

  // 상태 조회에 본인 기록 값이 함께 온다 (메뉴에 "등록한 기록"을 보여주기 위함)
  const state = api.apiGetStudentState("김하늘");
  eq("상태 조회에 기초 타수 포함", state.baseStrokes, 184);
  eq("상태 조회에 기초 정확도 포함", state.baseAccuracy, 94);
  eq("상태 조회에 최종 타수 포함", state.finalStrokes, 247);
  eq("상태 조회에 최종 정확도 포함", state.finalAccuracy, 97);
  check("상태 조회에 순위/점수는 없음", state.rank === undefined && state.totalScore === undefined,
    JSON.stringify(state));

  // 학생이 화면을 우회해 서버 함수를 직접 불러도 값이 바뀌지 않아야 한다
  function stored() {
    const row = api.readAllRecords_(sheet).filter(function (r) { return r.name === "김하늘"; })[0];
    return [row.baseStrokes, row.baseAccuracy, row.finalStrokes, row.finalAccuracy].join("/");
  }
  const before = stored();

  const retryBase = api.apiSaveBase("김하늘", trials([900, 99], [900, 99], [900, 99]));
  eq("기초 재등록 거부", retryBase.ok, false);
  eq("기초 재등록 뒤에도 값 그대로", stored(), before);

  const retryFinal = api.apiSaveFinal("김하늘", trials([900, 99], [900, 99], [900, 99]));
  eq("최종 재등록 거부", retryFinal.ok, false);
  eq("최종 재등록 뒤에도 값 그대로", stored(), before);

  // 교사는 언제든지 고칠 수 있다
  const teacherEdit = api.apiAdminSaveRecord(api.ADMIN_PASSWORD, "김하늘", {
    base: trials([200, 90], [200, 90], [200, 90]),
    final: trials([300, 98], [300, 98], [300, 98])
  });
  eq("교사는 수정 가능", teacherEdit.ok, true);
  eq("교사 수정 뒤 값이 바뀜", stored(), "200/90/300/98");

  // 교사가 최종 기록을 비우면 학생이 다시 등록할 수 있다
  api.apiAdminSaveRecord(api.ADMIN_PASSWORD, "김하늘", {
    base: trials([200, 90], [200, 90], [200, 90]),
    final: trials(["", ""], ["", ""], ["", ""])
  });
  const again = api.apiSaveFinal("김하늘", trials([260, 95], [260, 95], [260, 95]));
  eq("교사가 비운 뒤에는 학생이 다시 등록 가능", again.ok, true);

  // 관리 화면 진단 정보
  const data = api.apiAdminGetData(api.ADMIN_PASSWORD).data;
  check("진단: 스프레드시트 이름", !!data.diagnostics.spreadsheet, JSON.stringify(data.diagnostics));
  eq("진단: 학생명단 인원 수", data.diagnostics.roster, 5);
  eq("진단: 기록 시트 행 수", data.diagnostics.recordRows, 1);
  check("진단: 시트 이름 목록", data.diagnostics.sheets.indexOf("기록") > -1, data.diagnostics.sheets);
}

/* ---------------- 결과 요약 ---------------- */
console.log("\n" + "=".repeat(56));
if (failed === 0) {
  console.log("\x1b[32m\x1b[1m✅ 모든 테스트 통과: " + passed + "개\x1b[0m");
} else {
  console.log("\x1b[31m\x1b[1m❌ 실패 " + failed + "개 / 통과 " + passed + "개\x1b[0m");
  failures.forEach(function (f) { console.log("   - " + f); });
}
console.log("=".repeat(56));
process.exit(failed === 0 ? 0 : 1);
