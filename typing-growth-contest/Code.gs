/**
 * ============================================================
 *  ⌨️ 우리 반 타자 성장대회 (Typing Growth Contest)
 *  Google Apps Script + Google Sheets 웹앱
 *
 *  - 학생은 한컴타자에서 측정한 "타수 / 정확도"만 입력합니다.
 *  - 처음(기초) 기록과 마지막(최종) 기록을 비교해 성장 정도를 계산합니다.
 *  - 전체 순위는 교사 관리 화면에서만 볼 수 있습니다.
 *
 *  사용법은 README.md 를 참고하세요.
 * ============================================================
 */

/* ============================================================
 *  ① 교사가 직접 바꾸는 설정 (여기만 수정하면 됩니다)
 * ========================================================== */

/** 교사 관리 화면 비밀번호 (꼭 바꿔주세요!) */
const ADMIN_PASSWORD = "1234";

/** 웹앱 위쪽에 표시되는 제목 */
const APP_TITLE = "우리 반 타자 성장대회";

/**
 * 스프레드시트에 붙여넣은(바운드) 스크립트라면 비워두세요.
 * 따로 만든 독립 스크립트라면 시트 주소의 /d/ 와 /edit 사이 값을 넣으세요.
 * 예) const SPREADSHEET_ID = "1AbCdEfG...";
 */
const SPREADSHEET_ID = "";

/** 입력 가능한 타수의 최대값 */
const MAX_STROKES = 1000;

/* ============================================================
 *  ② 내부 설정 (보통 수정할 필요 없습니다)
 * ========================================================== */

const SHEET_STUDENTS = "학생명단";
const SHEET_RECORDS = "기록";

/** 기록 시트의 열 번호 (A=1) */
const COL = {
  NAME: 1,        // A 학생명
  B1S: 2,  B1A: 3,   // B,C 기초 1회 타수/정확도
  B2S: 4,  B2A: 5,   // D,E 기초 2회
  B3S: 6,  B3A: 7,   // F,G 기초 3회
  BS: 8,   BA: 9,    // H,I 기초 타수/정확도 (중간값)
  F1S: 10, F1A: 11,  // J,K 최종 1회
  F2S: 12, F2A: 13,  // L,M 최종 2회
  F3S: 14, F3A: 15,  // N,O 최종 3회
  FS: 16,  FA: 17,   // P,Q 최종 타수/정확도 (중간값)
  INC: 18,           // R 증가 타수
  RATE: 19,          // S 향상률(%)
  ACC_DELTA: 20,     // T 정확도 변화(%p)
  INC_SCORE: 21,     // U 증가량 점수(50점)
  RATE_SCORE: 22,    // V 향상률 점수(40점)
  ACC_SCORE: 23,     // W 정확도 점수(10점)
  TOTAL: 24,         // X 성장점수(100점)
  RANK: 25,          // Y 최종 순위
  UPDATED: 26        // Z 마지막 수정시간
};
const RECORD_LAST_COL = 26;

const RECORD_HEADERS = [
  "학생명",
  "기초1 타수", "기초1 정확도",
  "기초2 타수", "기초2 정확도",
  "기초3 타수", "기초3 정확도",
  "기초 타수", "기초 정확도",
  "최종1 타수", "최종1 정확도",
  "최종2 타수", "최종2 정확도",
  "최종3 타수", "최종3 정확도",
  "최종 타수", "최종 정확도",
  "증가 타수", "향상률(%)", "정확도 변화(%p)",
  "증가량 점수", "향상률 점수", "정확도 점수",
  "성장점수", "최종 순위", "마지막 수정시간"
];

const SAMPLE_STUDENTS = ["김하늘", "이준서", "박서윤", "정민재", "최유나"];

/* ============================================================
 *  ③ 웹앱 진입점
 * ========================================================== */

function doGet(e) {
  const template = HtmlService.createTemplateFromFile("index");
  template.appTitle = APP_TITLE;
  return template
    .evaluate()
    .setTitle(APP_TITLE)
    .addMetaTag("viewport", "width=device-width, initial-scale=1, viewport-fit=cover")
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

/** index.html 안에서 style / script / admin 파일을 불러오기 위한 도우미 */
function include(filename) {
  return HtmlService.createHtmlOutputFromFile(filename).getContent();
}

/** 시트를 열면 상단에 교사용 메뉴를 추가합니다. */
function onOpen() {
  try {
    SpreadsheetApp.getUi()
      .createMenu("⌨️ 타자 성장대회")
      .addItem("① 시트 초기화 (처음 1회)", "initializeSheets")
      .addItem("② 순위 다시 계산", "menuRecalculate_")
      .addToUi();
  } catch (err) {
    // 시트가 아닌 곳에서 실행되면 무시합니다.
  }
}

function menuRecalculate_() {
  const result = recalculateAll_();
  SpreadsheetApp.getUi().alert(
    "순위를 다시 계산했습니다.\n\n기록 완료 학생: " + result.completed + "명"
  );
}

/* ============================================================
 *  ④ 시트 준비 (처음 1회 실행)
 * ========================================================== */

/**
 * 필요한 시트를 자동으로 만들어 줍니다.
 * Apps Script 편집기에서 이 함수를 한 번 실행하세요.
 */
function initializeSheets() {
  const ss = getSpreadsheet_();

  // ----- 학생명단 시트 -----
  let students = ss.getSheetByName(SHEET_STUDENTS);
  if (!students) {
    students = ss.insertSheet(SHEET_STUDENTS);
    students.getRange(1, 1, 1, 2).setValues([["번호", "이름"]]);
    const rows = SAMPLE_STUDENTS.map(function (name, i) { return [i + 1, name]; });
    students.getRange(2, 1, rows.length, 2).setValues(rows);
    students.setColumnWidth(1, 70);
    students.setColumnWidth(2, 160);
  } else {
    students.getRange(1, 1, 1, 2).setValues([["번호", "이름"]]);
  }
  styleHeader_(students, 2);

  // ----- 기록 시트 -----
  let records = ss.getSheetByName(SHEET_RECORDS);
  if (!records) {
    records = ss.insertSheet(SHEET_RECORDS);
  }
  records.getRange(1, 1, 1, RECORD_LAST_COL).setValues([RECORD_HEADERS]);
  styleHeader_(records, RECORD_LAST_COL);
  records.setColumnWidth(COL.NAME, 110);
  records.setColumnWidth(COL.UPDATED, 150);

  // 기본 시트(Sheet1 / 시트1)가 비어 있으면 정리합니다.
  ss.getSheets().forEach(function (sheet) {
    const name = sheet.getName();
    const isDefault = (name === "Sheet1" || name === "시트1");
    if (isDefault && ss.getSheets().length > 1 && sheet.getLastRow() === 0) {
      ss.deleteSheet(sheet);
    }
  });

  try {
    ss.toast("시트 준비가 끝났습니다. 학생명단 시트에 우리 반 학생 이름을 넣어주세요!", "✅ 초기화 완료", 8);
  } catch (err) { /* 편집기에서 실행한 경우 */ }

  return "학생명단 / 기록 시트를 준비했습니다.";
}

function styleHeader_(sheet, columns) {
  sheet.getRange(1, 1, 1, columns)
    .setFontWeight("bold")
    .setBackground("#e8f0ff")
    .setHorizontalAlignment("center");
  sheet.setFrozenRows(1);
}

/* ============================================================
 *  ⑤ 스프레드시트 접근 도우미
 * ========================================================== */

function getSpreadsheet_() {
  const ss = SPREADSHEET_ID
    ? SpreadsheetApp.openById(SPREADSHEET_ID)
    : SpreadsheetApp.getActive();
  if (!ss) {
    throw new Error(
      "스프레드시트를 찾을 수 없습니다. 시트에서 [확장 프로그램 > Apps Script]로 만든 스크립트인지 확인하거나, " +
      "Code.gs 위쪽의 SPREADSHEET_ID 에 시트 ID를 넣어주세요."
    );
  }
  return ss;
}

function getSheet_(name) {
  const sheet = getSpreadsheet_().getSheetByName(name);
  if (!sheet) {
    throw new Error("'" + name + "' 시트가 없습니다. Apps Script 편집기에서 initializeSheets() 를 먼저 실행해주세요.");
  }
  return sheet;
}

/** 학생명단 시트에서 이름 목록을 읽습니다. */
function getStudents_() {
  const sheet = getSheet_(SHEET_STUDENTS);
  const lastRow = sheet.getLastRow();
  if (lastRow < 2) return [];

  const values = sheet.getRange(2, 1, lastRow - 1, 2).getValues();
  const seen = {};
  const list = [];
  values.forEach(function (row) {
    const name = String(row[1] == null ? "" : row[1]).trim();
    if (!name || seen[name]) return;
    seen[name] = true;
    list.push({ number: row[0] === "" || row[0] == null ? "" : row[0], name: name });
  });
  return list;
}

function isStudentName_(name) {
  return getStudents_().some(function (s) { return s.name === name; });
}

/** 기록 시트에서 학생 이름이 있는 행 번호를 찾습니다. 없으면 0 */
function findRecordRow_(sheet, name) {
  const lastRow = sheet.getLastRow();
  if (lastRow < 2) return 0;
  const names = sheet.getRange(2, 1, lastRow - 1, 1).getValues();
  for (let i = 0; i < names.length; i++) {
    if (String(names[i][0] == null ? "" : names[i][0]).trim() === name) return i + 2;
  }
  return 0;
}

/** 행이 없으면 새로 만들고 행 번호를 돌려줍니다. */
function ensureRecordRow_(sheet, name) {
  let row = findRecordRow_(sheet, name);
  if (row) return row;
  const blank = new Array(RECORD_LAST_COL).fill("");
  blank[COL.NAME - 1] = name;
  sheet.appendRow(blank);
  return sheet.getLastRow();
}

/** 기록 시트 전체를 읽어 계산용 객체 배열로 바꿉니다. */
function readAllRecords_(sheet) {
  const lastRow = sheet.getLastRow();
  if (lastRow < 2) return [];
  const values = sheet.getRange(2, 1, lastRow - 1, RECORD_LAST_COL).getValues();
  const list = [];
  values.forEach(function (row, i) {
    const name = String(row[COL.NAME - 1] == null ? "" : row[COL.NAME - 1]).trim();
    if (!name) return;
    list.push({
      row: i + 2,
      name: name,
      baseTrials: [
        { strokes: row[COL.B1S - 1], accuracy: row[COL.B1A - 1] },
        { strokes: row[COL.B2S - 1], accuracy: row[COL.B2A - 1] },
        { strokes: row[COL.B3S - 1], accuracy: row[COL.B3A - 1] }
      ],
      finalTrials: [
        { strokes: row[COL.F1S - 1], accuracy: row[COL.F1A - 1] },
        { strokes: row[COL.F2S - 1], accuracy: row[COL.F2A - 1] },
        { strokes: row[COL.F3S - 1], accuracy: row[COL.F3A - 1] }
      ],
      baseStrokes: row[COL.BS - 1],
      baseAccuracy: row[COL.BA - 1],
      finalStrokes: row[COL.FS - 1],
      finalAccuracy: row[COL.FA - 1],
      updatedAt: row[COL.UPDATED - 1]
    });
  });
  return list;
}

function nowText_() {
  const tz = (function () {
    try { return getSpreadsheet_().getSpreadsheetTimeZone(); } catch (e) { return "Asia/Seoul"; }
  })();
  return Utilities.formatDate(new Date(), tz, "yyyy-MM-dd HH:mm");
}

/* ============================================================
 *  ⑥ 계산 로직 (순수 함수 – 시트 없이도 동작하며 테스트 가능)
 * ========================================================== */

function isNumeric_(value) {
  if (value === null || value === undefined || value === "") return false;
  if (typeof value === "number") return isFinite(value);
  const text = String(value).trim();
  if (text === "") return false;
  return isFinite(Number(text));
}

function toNumber_(value) {
  return Number(String(value).trim());
}

/** 소수점 첫째 자리까지 반올림 */
function round1_(value) {
  const n = Number(value);
  if (!isFinite(n)) return 0;
  return Math.round((n + Number.EPSILON * Math.sign(n)) * 10) / 10;
}

/**
 * 3회 기록을 검사합니다.
 * 성공: { ok:true, trials:[{strokes,accuracy} x3] }
 * 실패: { ok:false, message:"..." }
 */
function validateTrials_(trials, label) {
  const title = label || "기록";
  if (!trials || trials.length !== 3) {
    return { ok: false, message: title + " 3회를 모두 입력해주세요." };
  }

  const parsed = [];
  for (let i = 0; i < 3; i++) {
    const no = (i + 1) + "회";
    const raw = trials[i] || {};
    const strokesText = String(raw.strokes == null ? "" : raw.strokes).trim();
    const accuracyText = String(raw.accuracy == null ? "" : raw.accuracy).trim();

    if (strokesText === "") {
      return { ok: false, message: no + " 타수가 비어 있어요. 3회 기록을 모두 입력해주세요." };
    }
    if (accuracyText === "") {
      return { ok: false, message: no + " 정확도가 비어 있어요. 3회 기록을 모두 입력해주세요." };
    }
    if (!/^\d+$/.test(strokesText)) {
      return { ok: false, message: no + " 타수는 0~" + MAX_STROKES + " 사이의 숫자로 입력해주세요. (소수점 없이)" };
    }
    if (!/^\d+(\.\d+)?$/.test(accuracyText)) {
      return { ok: false, message: no + " 정확도는 0~100 사이의 숫자로 입력해주세요." };
    }

    const strokes = Number(strokesText);
    const accuracy = Number(accuracyText);
    if (strokes < 0 || strokes > MAX_STROKES) {
      return { ok: false, message: no + " 타수는 0~" + MAX_STROKES + " 사이의 숫자로 입력해주세요." };
    }
    if (accuracy < 0 || accuracy > 100) {
      return { ok: false, message: no + " 정확도는 0~100 사이의 숫자로 입력해주세요." };
    }
    parsed.push({ strokes: strokes, accuracy: accuracy });
  }
  return { ok: true, trials: parsed };
}

/**
 * 3회 중 "타수의 중간값" 기록을 고릅니다.
 * 평균이 아니라 중간값을 쓰고, 정확도는 그 회차의 정확도를 그대로 사용합니다.
 */
function pickMedianTrial_(trials) {
  const sorted = trials
    .map(function (trial, index) { return { trial: trial, index: index }; })
    .sort(function (a, b) {
      if (a.trial.strokes !== b.trial.strokes) return a.trial.strokes - b.trial.strokes;
      return a.index - b.index;
    });
  const picked = sorted[1];
  return {
    strokes: picked.trial.strokes,
    accuracy: picked.trial.accuracy,
    trialNo: picked.index + 1
  };
}

/** 최종 정확도 → 정확도 점수(10점 만점) */
function accuracyScore_(finalAccuracy) {
  if (finalAccuracy >= 98) return 10;
  if (finalAccuracy >= 96) return 8;
  if (finalAccuracy >= 94) return 6;
  if (finalAccuracy >= 92) return 4;
  if (finalAccuracy >= 90) return 2;
  return 0;
}

/**
 * 반 전체 기록으로 성장 결과 + 성장점수 + 순위를 계산합니다.
 * students: [{name, baseStrokes, baseAccuracy, finalStrokes, finalAccuracy}]
 * 반환: 입력과 같은 순서의 결과 배열
 */
function computeResults_(students) {
  const results = (students || []).map(function (student) {
    const hasBase = isNumeric_(student.baseStrokes) && isNumeric_(student.baseAccuracy);
    const hasFinal = hasBase && isNumeric_(student.finalStrokes) && isNumeric_(student.finalAccuracy);

    const result = {
      name: student.name,
      row: student.row || 0,
      hasBase: hasBase,
      hasFinal: hasFinal,
      baseStrokes: hasBase ? toNumber_(student.baseStrokes) : null,
      baseAccuracy: hasBase ? toNumber_(student.baseAccuracy) : null,
      finalStrokes: hasFinal ? toNumber_(student.finalStrokes) : null,
      finalAccuracy: hasFinal ? toNumber_(student.finalAccuracy) : null,
      increase: null,
      rate: null,
      accuracyDelta: null,
      increaseScore: null,
      rateScore: null,
      accuracyScore: null,
      totalScore: null,
      rank: null,
      updatedAt: student.updatedAt || ""
    };

    if (hasFinal) {
      result.increase = result.finalStrokes - result.baseStrokes;
      // 기초 타수가 0이면 나눗셈을 할 수 없으므로 향상률은 0으로 둡니다.
      result.rate = result.baseStrokes > 0
        ? round1_((result.increase / result.baseStrokes) * 100)
        : 0;
      result.accuracyDelta = round1_(result.finalAccuracy - result.baseAccuracy);
      result.accuracyScore = accuracyScore_(result.finalAccuracy);
    }
    return result;
  });

  const completed = results.filter(function (r) { return r.hasFinal; });

  // 반에서 가장 큰 증가량 / 향상률을 기준으로 정규화합니다.
  const maxIncrease = completed.reduce(function (max, r) {
    return r.increase > max ? r.increase : max;
  }, 0);
  const maxRate = completed.reduce(function (max, r) {
    return r.rate > max ? r.rate : max;
  }, 0);

  completed.forEach(function (r) {
    r.increaseScore = (r.increase > 0 && maxIncrease > 0)
      ? round1_((r.increase / maxIncrease) * 50)
      : 0;
    r.rateScore = (r.rate > 0 && maxRate > 0)
      ? round1_((r.rate / maxRate) * 40)
      : 0;
    r.totalScore = Math.min(100, round1_(r.increaseScore + r.rateScore + r.accuracyScore));
  });

  // 성장점수 → 최종 정확도 → 증가 타수 → 향상률 순으로 정렬
  const ordered = completed.slice().sort(compareForRank_);
  for (let i = 0; i < ordered.length; i++) {
    if (i > 0 && isSameRankKey_(ordered[i], ordered[i - 1])) {
      ordered[i].rank = ordered[i - 1].rank;
    } else {
      ordered[i].rank = i + 1;
    }
  }

  return results;
}

function compareForRank_(a, b) {
  if (b.totalScore !== a.totalScore) return b.totalScore - a.totalScore;
  if (b.finalAccuracy !== a.finalAccuracy) return b.finalAccuracy - a.finalAccuracy;
  if (b.increase !== a.increase) return b.increase - a.increase;
  if (b.rate !== a.rate) return b.rate - a.rate;
  return String(a.name).localeCompare(String(b.name), "ko");
}

function isSameRankKey_(a, b) {
  return a.totalScore === b.totalScore
    && a.finalAccuracy === b.finalAccuracy
    && a.increase === b.increase
    && a.rate === b.rate;
}

/** 시상 결과(같은 학생이 여러 상을 받을 수 있습니다) */
function computeAwards_(results) {
  const completed = (results || []).filter(function (r) { return r.hasFinal; });
  function best(valueOf) {
    if (!completed.length) return { names: [], value: null };
    const top = completed.reduce(function (max, r) {
      const v = valueOf(r);
      return v > max ? v : max;
    }, -Infinity);
    return {
      names: completed.filter(function (r) { return valueOf(r) === top; })
        .map(function (r) { return r.name; }),
      value: top
    };
  }
  return {
    growthKing: best(function (r) { return r.totalScore; }),
    rateKing: best(function (r) { return r.rate; }),
    accuracyKing: best(function (r) { return r.finalAccuracy; }),
    speedKing: best(function (r) { return r.finalStrokes; })
  };
}

/* ============================================================
 *  ⑦ 전체 재계산 (기록이 바뀔 때마다 실행)
 * ========================================================== */

function recalculateAll_() {
  const sheet = getSheet_(SHEET_RECORDS);
  const records = readAllRecords_(sheet);
  const results = computeResults_(records);

  if (!records.length) return { completed: 0, results: [] };

  const firstRow = records[0].row;
  const lastRow = records[records.length - 1].row;
  const height = lastRow - firstRow + 1;

  // R~Y 열(증가 타수 ~ 최종 순위)만 한 번에 다시 씁니다.
  const width = COL.RANK - COL.INC + 1;
  const block = [];
  for (let i = 0; i < height; i++) block.push(new Array(width).fill(""));

  results.forEach(function (r) {
    if (!r.hasFinal) return;
    block[r.row - firstRow] = [
      r.increase, r.rate, r.accuracyDelta,
      r.increaseScore, r.rateScore, r.accuracyScore,
      r.totalScore, r.rank
    ];
  });

  sheet.getRange(firstRow, COL.INC, height, width).setValues(block);

  return {
    completed: results.filter(function (r) { return r.hasFinal; }).length,
    results: results
  };
}

/* ============================================================
 *  ⑧ 학생용 API (google.script.run 으로 호출)
 * ========================================================== */

function apiGetStudents() {
  return safe_(function () {
    return { ok: true, appTitle: APP_TITLE, students: getStudents_() };
  });
}

/** 이 학생이 기초/최종 기록을 등록했는지 알려줍니다. */
function apiGetStudentState(name) {
  return safe_(function () {
    const student = String(name || "").trim();
    if (!student) return { ok: false, message: "이름을 먼저 선택해주세요." };
    const sheet = getSheet_(SHEET_RECORDS);
    const row = findRecordRow_(sheet, student);
    if (!row) return { ok: true, hasBase: false, hasFinal: false };
    const values = sheet.getRange(row, 1, 1, RECORD_LAST_COL).getValues()[0];
    return {
      ok: true,
      hasBase: isNumeric_(values[COL.BS - 1]) && isNumeric_(values[COL.BA - 1]),
      hasFinal: isNumeric_(values[COL.FS - 1]) && isNumeric_(values[COL.FA - 1])
    };
  });
}

function apiSaveBase(name, trials) {
  return safe_(function () {
    return saveRecord_(name, trials, "base");
  });
}

function apiSaveFinal(name, trials) {
  return safe_(function () {
    return saveRecord_(name, trials, "final");
  });
}

/**
 * 기초/최종 기록 저장 (학생용).
 * 이미 등록된 기록은 학생이 덮어쓸 수 없습니다. (교사만 수정 가능)
 */
function saveRecord_(name, trials, kind) {
  const student = String(name || "").trim();
  const label = kind === "base" ? "기초 기록" : "최종 기록";

  if (!student) return { ok: false, message: "이름을 먼저 선택해주세요." };
  if (!isStudentName_(student)) {
    return { ok: false, message: "학생 명단에 없는 이름이에요. 선생님께 알려주세요." };
  }

  const check = validateTrials_(trials, label);
  if (!check.ok) return { ok: false, message: check.message };

  return withLock_(function () {
    const sheet = getSheet_(SHEET_RECORDS);
    const row = ensureRecordRow_(sheet, student);
    const values = sheet.getRange(row, 1, 1, RECORD_LAST_COL).getValues()[0];

    const hasBase = isNumeric_(values[COL.BS - 1]) && isNumeric_(values[COL.BA - 1]);
    const hasFinal = isNumeric_(values[COL.FS - 1]) && isNumeric_(values[COL.FA - 1]);

    if (kind === "base" && hasBase) {
      return {
        ok: false,
        duplicated: true,
        message: "이미 기초 기록이 등록되어 있습니다. 고쳐야 한다면 선생님께 말씀드려 주세요."
      };
    }
    if (kind === "final") {
      if (!hasBase) {
        return { ok: false, message: "기초 기록을 먼저 등록해주세요." };
      }
      if (hasFinal) {
        return {
          ok: false,
          duplicated: true,
          message: "이미 최종 기록이 등록되어 있습니다. 고쳐야 한다면 선생님께 말씀드려 주세요."
        };
      }
    }

    const median = pickMedianTrial_(check.trials);
    const startCol = kind === "base" ? COL.B1S : COL.F1S;
    sheet.getRange(row, startCol, 1, 8).setValues([[
      check.trials[0].strokes, check.trials[0].accuracy,
      check.trials[1].strokes, check.trials[1].accuracy,
      check.trials[2].strokes, check.trials[2].accuracy,
      median.strokes, median.accuracy
    ]]);
    sheet.getRange(row, COL.UPDATED).setValue(nowText_());

    recalculateAll_();

    return {
      ok: true,
      kind: kind,
      strokes: median.strokes,
      accuracy: median.accuracy,
      trialNo: median.trialNo,
      result: kind === "final" ? readStudentResult_(student) : null
    };
  });
}

/** 학생 본인의 성장 결과 (다른 학생 정보/순위는 절대 포함하지 않습니다) */
function apiGetMyResult(name) {
  return safe_(function () {
    const student = String(name || "").trim();
    if (!student) return { ok: false, message: "이름을 먼저 선택해주세요." };
    recalculateAll_();
    return { ok: true, result: readStudentResult_(student) };
  });
}

function readStudentResult_(name) {
  const sheet = getSheet_(SHEET_RECORDS);
  const records = readAllRecords_(sheet);
  const results = computeResults_(records);
  const mine = results.filter(function (r) { return r.name === name; })[0];

  if (!mine) return { state: "none" };
  if (!mine.hasBase) return { state: "none" };
  if (!mine.hasFinal) {
    return {
      state: "base",
      baseStrokes: mine.baseStrokes,
      baseAccuracy: mine.baseAccuracy
    };
  }
  // 순위(rank)는 학생에게 보내지 않습니다.
  return {
    state: "done",
    baseStrokes: mine.baseStrokes,
    baseAccuracy: mine.baseAccuracy,
    finalStrokes: mine.finalStrokes,
    finalAccuracy: mine.finalAccuracy,
    increase: mine.increase,
    rate: mine.rate,
    accuracyDelta: mine.accuracyDelta,
    increaseScore: mine.increaseScore,
    rateScore: mine.rateScore,
    accuracyScore: mine.accuracyScore,
    totalScore: mine.totalScore
  };
}

/* ============================================================
 *  ⑨ 교사 관리 API
 * ========================================================== */

function checkPassword_(password) {
  return String(password == null ? "" : password) === String(ADMIN_PASSWORD);
}

function apiAdminLogin(password) {
  return safe_(function () {
    if (!checkPassword_(password)) {
      return { ok: false, message: "비밀번호가 올바르지 않습니다." };
    }
    return { ok: true };
  });
}

function apiAdminGetData(password) {
  return safe_(function () {
    if (!checkPassword_(password)) return { ok: false, message: "비밀번호가 올바르지 않습니다." };
    return { ok: true, data: buildAdminData_() };
  });
}

/** 교사가 [순위 다시 계산]을 눌렀을 때 */
function apiAdminRecalculate(password) {
  return safe_(function () {
    if (!checkPassword_(password)) return { ok: false, message: "비밀번호가 올바르지 않습니다." };
    return { ok: true, data: buildAdminData_() };
  });
}

/**
 * 관리 화면에 보여줄 전체 데이터.
 * 학생명단에 있지만 아직 기록이 없는 학생도 함께 보여줍니다.
 */
function buildAdminData_() {
  recalculateAll_();

  const sheet = getSheet_(SHEET_RECORDS);
  const records = readAllRecords_(sheet);
  const results = computeResults_(records);
  const byName = {};
  results.forEach(function (r, i) {
    r.baseTrials = records[i].baseTrials;
    r.finalTrials = records[i].finalTrials;
    byName[r.name] = r;
  });

  const roster = getStudents_();
  const rows = [];
  roster.forEach(function (student) {
    rows.push(byName[student.name] || emptyResult_(student.name));
    delete byName[student.name];
  });
  // 명단에서 지워졌지만 기록이 남아 있는 학생도 표시합니다.
  Object.keys(byName).forEach(function (name) {
    const extra = byName[name];
    extra.notInRoster = true;
    rows.push(extra);
  });

  rows.sort(function (a, b) {
    if (a.hasFinal && b.hasFinal) return compareForRank_(a, b);
    if (a.hasFinal) return -1;
    if (b.hasFinal) return 1;
    if (a.hasBase !== b.hasBase) return a.hasBase ? -1 : 1;
    return String(a.name).localeCompare(String(b.name), "ko");
  });

  return {
    rows: rows,
    awards: computeAwards_(results),
    summary: {
      total: rows.length,
      baseDone: rows.filter(function (r) { return r.hasBase; }).length,
      finalDone: rows.filter(function (r) { return r.hasFinal; }).length
    },
    updatedAt: nowText_()
  };
}

function emptyResult_(name) {
  return {
    name: name, row: 0, hasBase: false, hasFinal: false,
    baseStrokes: null, baseAccuracy: null, finalStrokes: null, finalAccuracy: null,
    increase: null, rate: null, accuracyDelta: null,
    increaseScore: null, rateScore: null, accuracyScore: null,
    totalScore: null, rank: null, updatedAt: "",
    baseTrials: [{ strokes: "", accuracy: "" }, { strokes: "", accuracy: "" }, { strokes: "", accuracy: "" }],
    finalTrials: [{ strokes: "", accuracy: "" }, { strokes: "", accuracy: "" }, { strokes: "", accuracy: "" }]
  };
}

/**
 * 교사가 학생 기록을 수정합니다.
 * payload = { base: [{strokes,accuracy} x3] | null, final: [...] | null }
 * 해당 구간을 모두 비우면 "등록 안 함" 상태로 되돌립니다.
 */
function apiAdminSaveRecord(password, name, payload) {
  return safe_(function () {
    if (!checkPassword_(password)) return { ok: false, message: "비밀번호가 올바르지 않습니다." };

    const student = String(name || "").trim();
    if (!student) return { ok: false, message: "학생 이름이 없습니다." };

    const data = payload || {};
    const baseState = sectionState_(data.base);
    const finalState = sectionState_(data.final);

    if (baseState === "partial") {
      return { ok: false, message: "기초 기록은 3회 타수와 정확도를 모두 채우거나, 모두 비워주세요." };
    }
    if (finalState === "partial") {
      return { ok: false, message: "최종 기록은 3회 타수와 정확도를 모두 채우거나, 모두 비워주세요." };
    }

    let baseCheck = null;
    let finalCheck = null;
    if (baseState === "filled") {
      baseCheck = validateTrials_(data.base, "기초 기록");
      if (!baseCheck.ok) return { ok: false, message: "[기초] " + baseCheck.message };
    }
    if (finalState === "filled") {
      finalCheck = validateTrials_(data.final, "최종 기록");
      if (!finalCheck.ok) return { ok: false, message: "[최종] " + finalCheck.message };
    }
    if (finalState === "filled" && baseState !== "filled") {
      return { ok: false, message: "최종 기록만 저장할 수 없습니다. 기초 기록도 함께 입력해주세요." };
    }

    return withLock_(function () {
      const sheet = getSheet_(SHEET_RECORDS);
      const row = ensureRecordRow_(sheet, student);

      writeSection_(sheet, row, COL.B1S, baseCheck);
      writeSection_(sheet, row, COL.F1S, finalCheck);
      sheet.getRange(row, COL.UPDATED).setValue(nowText_());

      return { ok: true, data: buildAdminData_() };
    });
  });
}

/** "filled"(3회 모두 입력) / "empty"(모두 비움) / "partial"(일부만 입력) */
function sectionState_(trials) {
  if (!trials || !trials.length) return "empty";
  let filled = 0;
  let blank = 0;
  trials.forEach(function (trial) {
    [trial.strokes, trial.accuracy].forEach(function (value) {
      if (String(value == null ? "" : value).trim() === "") blank++;
      else filled++;
    });
  });
  if (filled === 0) return "empty";
  if (blank === 0) return "filled";
  return "partial";
}

function writeSection_(sheet, row, startCol, check) {
  if (check) {
    const median = pickMedianTrial_(check.trials);
    sheet.getRange(row, startCol, 1, 8).setValues([[
      check.trials[0].strokes, check.trials[0].accuracy,
      check.trials[1].strokes, check.trials[1].accuracy,
      check.trials[2].strokes, check.trials[2].accuracy,
      median.strokes, median.accuracy
    ]]);
  } else {
    sheet.getRange(row, startCol, 1, 8).setValues([["", "", "", "", "", "", "", ""]]);
  }
}

/** 학생 기록 삭제 (행 자체를 지웁니다) */
function apiAdminDeleteRecord(password, name) {
  return safe_(function () {
    if (!checkPassword_(password)) return { ok: false, message: "비밀번호가 올바르지 않습니다." };
    const student = String(name || "").trim();

    return withLock_(function () {
      const sheet = getSheet_(SHEET_RECORDS);
      const row = findRecordRow_(sheet, student);
      if (!row) return { ok: false, message: "삭제할 기록이 없습니다." };
      sheet.deleteRow(row);
      return { ok: true, data: buildAdminData_() };
    });
  });
}

/** 전체 결과 CSV (엑셀에서 열 수 있도록 클라이언트에서 파일로 저장) */
function apiAdminGetCsv(password) {
  return safe_(function () {
    if (!checkPassword_(password)) return { ok: false, message: "비밀번호가 올바르지 않습니다." };
    const data = buildAdminData_();
    const header = [
      "순위", "이름", "기초 타수", "기초 정확도", "최종 타수", "최종 정확도",
      "증가 타수", "향상률(%)", "정확도 변화(%p)",
      "증가량 점수", "향상률 점수", "정확도 점수", "성장점수", "마지막 수정시간"
    ];
    const lines = [header.map(csvCell_).join(",")];
    data.rows.forEach(function (r) {
      lines.push([
        r.rank, r.name, r.baseStrokes, r.baseAccuracy, r.finalStrokes, r.finalAccuracy,
        r.increase, r.rate, r.accuracyDelta,
        r.increaseScore, r.rateScore, r.accuracyScore, r.totalScore, r.updatedAt
      ].map(csvCell_).join(","));
    });
    return {
      ok: true,
      csv: lines.join("\r\n"),
      filename: "타자성장대회_결과_" + nowText_().replace(/[^0-9]/g, "").slice(0, 8) + ".csv"
    };
  });
}

function csvCell_(value) {
  if (value === null || value === undefined) return "";
  const text = String(value);
  if (/[",\r\n]/.test(text)) return '"' + text.replace(/"/g, '""') + '"';
  return text;
}

/* ============================================================
 *  ⑩ 공통 오류 처리
 * ========================================================== */

/** 여러 학생이 동시에 저장할 때 기록이 섞이지 않도록 잠금을 겁니다. */
function withLock_(fn) {
  const lock = LockService.getScriptLock();
  try {
    lock.waitLock(20000);
  } catch (err) {
    return { ok: false, message: "지금 다른 친구가 저장하고 있어요. 잠시 뒤에 다시 눌러주세요." };
  }
  try {
    return fn();
  } finally {
    lock.releaseLock();
  }
}

function safe_(fn) {
  try {
    return fn();
  } catch (err) {
    return { ok: false, message: (err && err.message) ? err.message : "알 수 없는 오류가 발생했습니다." };
  }
}
