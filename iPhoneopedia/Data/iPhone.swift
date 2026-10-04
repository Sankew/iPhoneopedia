//
//  iPhoneData.swift
//  iPhoneopedia
//
//  Created by Sankeshwar Sivakumar  on 27/05/2022.
//

import Foundation
import SwiftUI

struct iPhone: Hashable, Codable, Identifiable {
    var id: Int
    var name: String
    var release_date: String
    var model: String
    var quote: String
    var description: String

    public var imageName: String
    var image: Image {
        Image(imageName)
    }
}
