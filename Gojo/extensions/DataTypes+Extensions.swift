    //
    //  DataTypes+Extensions.swift
    //  Gojo
    //
    //  Created by Harsh Vardhan  Goswami  on 27/08/24.
    //

import Foundation

extension Date {
    var date: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd"
        return dateFormatter.string(from: self)
    }
}
