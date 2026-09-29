import Charts
import SwiftUI

/// Nineteen years of iPhones at a glance.
struct TrendsView: View {
    private let store = CatalogStore.shared

    var body: some View {
        let models = store.models
        List {
            Section {
                Chart(models.filter { $0.launchPriceUSD != nil }) { model in
                    PointMark(x: .value("Released", model.released), y: .value("Price (USD)", model.launchPriceUSD ?? 0))
                }
                .frame(height: 220)
            } header: {
                Text("US launch price")
            } footer: {
                Text("Starting price at launch. iPhone 3G through 6s were sold at two-year-contract prices.")
            }

            Section("Screen size (inches)") {
                Chart(models.filter { $0.displayInches != nil }) { model in
                    PointMark(x: .value("Released", model.released), y: .value("Inches", model.displayInches ?? 0))
                }
                .frame(height: 220)
            }

            Section("Models per year") {
                Chart(models) { model in
                    BarMark(x: .value("Year", model.released, unit: .year), y: .value("Models", 1))
                }
                .frame(height: 180)
            }
        }
        .navigationTitle("Trends")
    }
}

#Preview {
    NavigationStack { TrendsView() }
}
