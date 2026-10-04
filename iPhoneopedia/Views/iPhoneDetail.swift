//
//  iPhoneDetail.swift
//  iPhoneopedia
//
//  Created by Sankeshwar Sivakumar  on 27/05/2022.
//

import SwiftUI

struct iPhoneDetail: View {
    var iPhone: iPhone
    var body: some View {
            ScrollView {
                Image(iPhone.imageName)
                    .resizable()
                    .frame(width: 380, height: 380)
                VStack {
                    VStack(alignment: .leading) {
                        Text(iPhone.name)
                            .font(.title)

                        HStack {
                            Text(iPhone.model)
                            Spacer()
                            Text(iPhone.release_date)
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        Text(iPhone.quote)
                            .multilineTextAlignment(.center)

                        Divider()
                        Text("About iPhone")
                            .font(.title2)
                        Text(iPhone.description)
                        
                        Divider()
                    }
                    .padding()
                    Spacer()
                }
            }
            .navigationTitle(iPhone.name)
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct iPhoneDetail_Previews: PreviewProvider {
    static var previews: some View {
        iPhoneDetail(iPhone: iPhones[0])
    }
}
