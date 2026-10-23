import Foundation

enum XLSXCell {
    case text(String)
    case number(Decimal)
    case date(Date)
}

struct XLSXSheet {
    struct Column { var title: String; var width: Double; var style: Style }
    enum Style: Int { case general = 0, header = 1, date = 2, amount = 3 }
    var name: String
    var columns: [Column]
    var rows: [[XLSXCell]]
}

/// Minimal Office Open XML (.xlsx) writer: one worksheet, header row, number and date formats, frozen header and autofilter.
enum XLSXWriter {
    static func data(for sheet: XLSXSheet, calendar: Calendar = .app) -> Data {
        var zip = ZipWriter()
        zip.add("[Content_Types].xml", contentTypes)
        zip.add("_rels/.rels", rootRels)
        zip.add("xl/workbook.xml", workbook(name: sheet.name))
        zip.add("xl/_rels/workbook.xml.rels", workbookRels)
        zip.add("xl/styles.xml", styles)
        zip.add("xl/worksheets/sheet1.xml", sheetXML(sheet, calendar: calendar))
        return zip.finish()
    }

    static func escape(_ s: String) -> String {
        var r = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            case "\"": r += "&quot;"
            default:
                // Drop characters that are illegal in XML 1.0
                if ch.value >= 0x20 || ch == "\n" || ch == "\t" || ch == "\r" { r.unicodeScalars.append(ch) }
            }
        }
        return r
    }

    static func columnName(_ index: Int) -> String {
        var n = index, s = ""
        repeat { s = String(UnicodeScalar(UInt8(65 + n % 26))) + s; n = n / 26 - 1 } while n >= 0
        return s
    }

    /// Excel serial date (days since 1899-12-30), local time.
    static func serial(_ date: Date, calendar: Calendar) -> Double {
        let offset = Double(calendar.timeZone.secondsFromGMT(for: date))
        return (date.timeIntervalSince1970 + offset) / 86400 + 25569
    }

    private static func sheetXML(_ sheet: XLSXSheet, calendar: Calendar) -> String {
        var x = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        x += #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">"#
        x += #"<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>"#
        x += "<cols>"
        for (i, c) in sheet.columns.enumerated() { x += #"<col min="\#(i + 1)" max="\#(i + 1)" width="\#(c.width)" customWidth="1"/>"# }
        x += "</cols><sheetData>"
        x += #"<row r="1">"#
        for (i, c) in sheet.columns.enumerated() {
            x += #"<c r="\#(columnName(i))1" t="inlineStr" s="1"><is><t>\#(escape(c.title))</t></is></c>"#
        }
        x += "</row>"
        for (r, row) in sheet.rows.enumerated() {
            let rn = r + 2
            x += #"<row r="\#(rn)">"#
            for (i, cell) in row.enumerated() {
                let ref = "\(columnName(i))\(rn)"
                switch cell {
                case .text(let t):
                    if !t.isEmpty { x += #"<c r="\#(ref)" t="inlineStr"><is><t xml:space="preserve">\#(escape(t))</t></is></c>"# }
                case .number(let d):
                    x += #"<c r="\#(ref)" s="3"><v>\#(NSDecimalNumber(decimal: d).stringValue)</v></c>"#
                case .date(let d):
                    x += #"<c r="\#(ref)" s="2"><v>\#(serial(d, calendar: calendar))</v></c>"#
                }
            }
            x += "</row>"
        }
        x += "</sheetData>"
        if !sheet.columns.isEmpty {
            x += #"<autoFilter ref="A1:\#(columnName(sheet.columns.count - 1))\#(max(sheet.rows.count + 1, 1))"/>"#
        }
        x += "</worksheet>"
        return x
    }

    private static let contentTypes = #"""
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
    """#.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n    ", with: "\n")

    private static let rootRels = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#

    private static func workbook(name: String) -> String {
        #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="\#(escape(String(name.prefix(31))))" sheetId="1" r:id="rId1"/></sheets></workbook>"#
    }

    private static let workbookRels = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>"#

    private static let styles = ##"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="2"><numFmt numFmtId="164" formatCode="dd\.mm\.yyyy"/><numFmt numFmtId="165" formatCode="#,##0.00"/></numFmts><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>"##
}

/// Writes an uncompressed (stored) ZIP archive, which is valid for OOXML packages.
struct ZipWriter {
    private var body = Data()
    private var central = Data()
    private var count: UInt16 = 0

    private static let crcTable: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private func le<T: FixedWidthInteger>(_ v: T) -> Data {
        withUnsafeBytes(of: v.littleEndian) { Data($0) }
    }

    mutating func add(_ name: String, _ text: String) {
        let data = Data(text.utf8), nameData = Data(name.utf8)
        let crc = Self.crc32(data)
        let offset = UInt32(body.count)
        let time: UInt16 = 0, date: UInt16 = (46 << 9) | (1 << 5) | 1   // 2026-01-01
        var local = Data()
        local += le(UInt32(0x04034B50)); local += le(UInt16(20)); local += le(UInt16(0x0800)); local += le(UInt16(0))
        local += le(time); local += le(date); local += le(crc); local += le(UInt32(data.count)); local += le(UInt32(data.count))
        local += le(UInt16(nameData.count)); local += le(UInt16(0)); local += nameData
        body += local; body += data
        var c = Data()
        c += le(UInt32(0x02014B50)); c += le(UInt16(20)); c += le(UInt16(20)); c += le(UInt16(0x0800)); c += le(UInt16(0))
        c += le(time); c += le(date); c += le(crc); c += le(UInt32(data.count)); c += le(UInt32(data.count))
        c += le(UInt16(nameData.count)); c += le(UInt16(0)); c += le(UInt16(0)); c += le(UInt16(0)); c += le(UInt16(0))
        c += le(UInt32(0)); c += le(offset); c += nameData
        central += c
        count += 1
    }

    func finish() -> Data {
        var out = body
        let centralOffset = UInt32(body.count)
        out += central
        out += le(UInt32(0x06054B50)); out += le(UInt16(0)); out += le(UInt16(0))
        out += le(count); out += le(count); out += le(UInt32(central.count)); out += le(centralOffset); out += le(UInt16(0))
        return out
    }
}
