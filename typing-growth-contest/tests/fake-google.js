/**
 * 테스트용 가짜 Google Apps Script 환경.
 * Code.gs 를 수정하지 않고 그대로 Node.js 에서 실행하기 위한 최소 구현입니다.
 */

function blank(value) {
  return value === undefined || value === null ? "" : value;
}

class FakeRange {
  constructor(sheet, row, col, numRows, numCols) {
    this.sheet = sheet;
    this.row = row;
    this.col = col;
    this.numRows = numRows;
    this.numCols = numCols;
  }
  getValues() {
    const out = [];
    for (let r = 0; r < this.numRows; r++) {
      const line = [];
      for (let c = 0; c < this.numCols; c++) {
        const rowData = this.sheet.data[this.row - 1 + r] || [];
        line.push(blank(rowData[this.col - 1 + c]));
      }
      out.push(line);
    }
    return out;
  }
  setValues(values) {
    if (values.length !== this.numRows || values[0].length !== this.numCols) {
      throw new Error("setValues 크기가 range 와 다릅니다.");
    }
    for (let r = 0; r < this.numRows; r++) {
      const rowIndex = this.row - 1 + r;
      while (this.sheet.data.length <= rowIndex) this.sheet.data.push([]);
      for (let c = 0; c < this.numCols; c++) {
        this.sheet.data[rowIndex][this.col - 1 + c] = blank(values[r][c]);
      }
    }
    return this;
  }
  getValue() { return this.getValues()[0][0]; }
  setValue(value) { return this.setValues([[value]]); }
  // 서식 관련 메서드는 테스트에서 아무 일도 하지 않습니다.
  setFontWeight() { return this; }
  setBackground() { return this; }
  setHorizontalAlignment() { return this; }
  setNumberFormat() { return this; }
}

class FakeSheet {
  constructor(name) {
    this.name = name;
    this.data = [];
  }
  getName() { return this.name; }
  getLastRow() {
    for (let r = this.data.length - 1; r >= 0; r--) {
      const row = this.data[r] || [];
      if (row.some(function (cell) { return blank(cell) !== ""; })) return r + 1;
    }
    return 0;
  }
  getRange(row, col, numRows, numCols) {
    return new FakeRange(this, row, col, numRows === undefined ? 1 : numRows,
      numCols === undefined ? 1 : numCols);
  }
  appendRow(values) {
    const rowIndex = this.getLastRow();
    while (this.data.length <= rowIndex) this.data.push([]);
    this.data[rowIndex] = values.map(blank);
    return this;
  }
  deleteRow(row) { this.data.splice(row - 1, 1); return this; }
  setColumnWidth() { return this; }
  setFrozenRows() { return this; }
}

class FakeSpreadsheet {
  constructor() {
    this.sheets = [];
    this.toasts = [];
  }
  getName() { return "타자 성장대회"; }
  getSheetByName(name) {
    return this.sheets.filter(function (s) { return s.getName() === name; })[0] || null;
  }
  insertSheet(name) {
    const sheet = new FakeSheet(name);
    this.sheets.push(sheet);
    return sheet;
  }
  getSheets() { return this.sheets.slice(); }
  deleteSheet(sheet) {
    this.sheets = this.sheets.filter(function (s) { return s !== sheet; });
  }
  getSpreadsheetTimeZone() { return "Asia/Seoul"; }
  toast(message) { this.toasts.push(message); }
}

/* ---------- 가짜 드라이브 (캡처 사진 저장용) ---------- */

class FakeBlob {
  constructor(bytes, contentType, name) {
    this.bytes = bytes;
    this.contentType = contentType;
    this.name = name;
  }
  getBytes() { return this.bytes; }
  getContentType() { return this.contentType; }
  getName() { return this.name; }
}

class FakeFile {
  constructor(id, blob) {
    this.id = id;
    this.blob = blob;
    this.trashed = false;
  }
  getId() { return this.id; }
  getName() { return this.blob.getName(); }
  getUrl() { return "https://drive.google.com/file/d/" + this.id + "/view"; }
  getBlob() { return this.blob; }
  setTrashed(value) { this.trashed = value; return this; }
}

class FakeDrive {
  constructor() {
    this.folders = {};
    this.files = {};
    this.nextId = 1;
    this.failCreate = false;   // 권한 오류 상황을 흉내낼 때
  }
  _folder(name) {
    if (!this.folders[name]) {
      const drive = this;
      this.folders[name] = {
        name: name,
        createFile: function (blob) {
          if (drive.failCreate) throw new Error("드라이브 권한이 없습니다.");
          const id = "fileid" + String(drive.nextId++) + "0000000000000000000000";
          const file = new FakeFile(id, blob);
          drive.files[id] = file;
          return file;
        }
      };
    }
    return this.folders[name];
  }
  getFoldersByName(name) {
    const exists = !!this.folders[name];
    const folder = this.folders[name];
    let done = !exists;
    return {
      hasNext: function () { return !done; },
      next: function () { done = true; return folder; }
    };
  }
  createFolder(name) { return this._folder(name); }
  getFileById(id) {
    if (!this.files[id]) throw new Error("파일을 찾을 수 없습니다: " + id);
    return this.files[id];
  }
}

/** Code.gs 가 사용하는 전역 객체들을 만들어 줍니다. */
function createSandbox() {
  const spreadsheet = new FakeSpreadsheet();
  const drive = new FakeDrive();

  return {
    spreadsheet: spreadsheet,
    drive: drive,
    globals: {
      console: console,
      SpreadsheetApp: {
        getActive: function () { return spreadsheet; },
        openById: function () { return spreadsheet; },
        getUi: function () { throw new Error("UI 없음"); }
      },
      LockService: {
        getScriptLock: function () {
          return { waitLock: function () {}, releaseLock: function () {} };
        }
      },
      Utilities: {
        formatDate: function () { return "2026-03-05 09:30"; },
        base64Decode: function (text) { return Array.from(Buffer.from(String(text), "base64")); },
        base64Encode: function (bytes) { return Buffer.from(bytes).toString("base64"); },
        newBlob: function (bytes, contentType, name) { return new FakeBlob(bytes, contentType, name); }
      },
      DriveApp: drive,
      HtmlService: {
        createTemplateFromFile: function () { throw new Error("테스트에서는 사용하지 않습니다."); },
        createHtmlOutputFromFile: function () { throw new Error("테스트에서는 사용하지 않습니다."); },
        XFrameOptionsMode: { ALLOWALL: "ALLOWALL" }
      },
      Session: { getScriptTimeZone: function () { return "Asia/Seoul"; } }
    }
  };
}

module.exports = { createSandbox, FakeSheet, FakeSpreadsheet, FakeDrive };
