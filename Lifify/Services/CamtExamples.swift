import Foundation

/// Invented CAMT.053 text for the developer check.
/// It is not read from the user's store, files, or bank accounts.
enum CamtExamples {
    static let usesUserData = false

    /// First invented statement. Two Musterkaffee rows share the day and the amount.
    static var first: String {
        document(
            "beispiel-camt-a",
            ntry(date: "2026-03-03", amount: "7.40", debit: true, name: "Musterkaffee GmbH", iban: isoExampleIBAN, purpose: "MUSTER-A1", reference: "MUSTER-A1", info: "KARTENZAHLUNG"),
            ntry(date: "2026-03-03", amount: "7.40", debit: true, name: "Musterkaffee GmbH", iban: isoExampleIBAN, purpose: "MUSTER-A2", reference: "MUSTER-A2", info: "KARTENZAHLUNG"),
            ntry(date: "2026-03-03", amount: "21.00", debit: true, name: "Demoversand Nord", iban: bundesbankExampleIBAN, purpose: "SENDUNG-NORD", reference: "DEMO-N1", info: "KARTENZAHLUNG"),
            ntry(date: "2026-03-03", amount: "21.00", debit: true, name: "Demoversand Sued", iban: bundesbankExampleIBAN, purpose: "SENDUNG-SUED", reference: "DEMO-S1", info: "KARTENZAHLUNG"),
            ntry(date: "2026-03-05", amount: "4.80", debit: true, name: "Beispielbaeckerei", iban: isoExampleIBAN, purpose: "BROETCHEN", reference: "MUSTER-B1", info: "KARTENZAHLUNG"),
            ntry(date: "2026-03-10", amount: "2.20", debit: true, name: "Demoshop", iban: isoExampleIBAN, purpose: "ARTIKEL", reference: "MUSTER-C1", info: "KARTENZAHLUNG"),
            ntry(date: "2026-03-10", amount: "6.60", debit: true, name: "Demoabo", iban: isoExampleIBAN, purpose: "ABO", reference: "MUSTER-P1", info: "Umsatz vorgemerkt", pending: true)
        )
    }

    /// Later invented statement that overlaps the first. Only the new days should ingest.
    static var overlapping: String {
        document(
            "beispiel-camt-b",
            ntry(date: "2026-03-05", amount: "4.80", debit: true, name: "Beispielbaeckerei", iban: isoExampleIBAN, purpose: "BROETCHEN", reference: "MUSTER-B1", info: "KARTENZAHLUNG"),
            ntry(date: "2026-03-10", amount: "2.20", debit: true, name: "Demoshop", iban: isoExampleIBAN, purpose: "ARTIKEL", reference: "MUSTER-C1", info: "KARTENZAHLUNG"),
            ntry(date: "2026-03-12", amount: "13.70", debit: true, name: "Beispielmarkt", iban: isoExampleIBAN, purpose: "EINKAUF", reference: "MUSTER-D1", info: "KARTENZAHLUNG"),
            ntry(date: "2026-03-14", amount: "1800.00", debit: false, name: "Musterlohn GmbH", iban: bundesbankExampleIBAN, purpose: "LOHN MAERZ", reference: "MUSTER-E1", info: "GUTSCHRIFT")
        )
    }

    /// ISO 13616 example IBAN, not a user account.
    private static let isoExampleIBAN = "DE89370400440532013000"
    /// Bundesbank sample IBAN, not a user account.
    private static let bundesbankExampleIBAN = "DE02120300000000202051"

    private static func document(_ id: String, _ entries: String...) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02">
          <BkToCstmrStmt>
            <Stmt>
              <Id>\(id)</Id>
              <CreDtTm>2026-03-14T18:00:00</CreDtTm>
        \(entries.joined(separator: "\n"))
            </Stmt>
          </BkToCstmrStmt>
        </Document>
        """
    }

    private static func ntry(
        date: String,
        amount: String,
        debit: Bool,
        name: String,
        iban: String,
        purpose: String,
        reference: String,
        info: String,
        pending: Bool = false
    ) -> String {
        let ind = debit ? "DBIT" : "CRDT"
        let party = debit ? "Cdtr" : "Dbtr"
        let account = debit ? "CdtrAcct" : "DbtrAcct"
        let status = pending ? "PDNG" : "BOOK"
        return """
              <Ntry>
                <Amt Ccy="EUR">\(amount)</Amt>
                <CdtDbtInd>\(ind)</CdtDbtInd>
                <Sts>\(status)</Sts>
                <BookgDt><Dt>\(date)</Dt></BookgDt>
                <NtryDtls>
                  <TxDtls>
                    <Refs><EndToEndId>\(reference)</EndToEndId></Refs>
                    <RltdPties>
                      <\(party)><Nm>\(name)</Nm></\(party)>
                      <\(account)><Id><IBAN>\(iban)</IBAN></Id></\(account)>
                    </RltdPties>
                    <RmtInf><Ustrd>\(purpose)</Ustrd></RmtInf>
                  </TxDtls>
                </NtryDtls>
                <AddtlNtryInf>\(info)</AddtlNtryInf>
              </Ntry>
        """
    }
}
