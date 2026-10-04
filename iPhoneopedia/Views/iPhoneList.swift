//
//  iPhoneList.swift
//  iPhoneopedia
//
//  Created by Sankeshwar Sivakumar  on 27/05/2022.
//

import SwiftUI

struct iPhoneList: View {
    var body: some View {
        NavigationView{
            List(iPhones) { iPhone in
                NavigationLink{
                    iPhoneDetail(iPhone: iPhone)
                } label: {
                iPhoneRow(iPhone: iPhone)
                }
            }
            .navigationTitle("iPhoneopedia")
        }
    }
}

struct iPhoneList_Previews: PreviewProvider {
    static var previews: some View {
        iPhoneList()
    }
}
