//
//  iPhoneRow.swift
//  iPhoneopedia
//
//  Created by Sankeshwar Sivakumar  on 27/05/2022.
//

import SwiftUI

struct iPhoneRow: View {
    var iPhone: iPhone

    var body: some View {
        HStack {
            iPhone.image
                .resizable()
                .frame(width: 50, height: 50)
            Text(iPhone.name)
            Spacer()
        }
    }
}

struct iPhoneRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            iPhoneRow(iPhone: iPhones[0])
            iPhoneRow(iPhone: iPhones[1])
        }
        .previewLayout(.fixed(width: 300, height: 70))
    }
}
