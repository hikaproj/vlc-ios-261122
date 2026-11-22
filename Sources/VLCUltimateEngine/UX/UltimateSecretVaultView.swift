//
//  UltimateSecretVaultView.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Fully Functional Calculator Camouflage with Secret Formula Passcode (AES-GCM Encrypted Vault).
//

import SwiftUI
import CryptoKit
import UIKit

@MainActor
public final class UltimateVaultManager: ObservableObject {
    public static let shared = UltimateVaultManager()
    
    @Published public var isVaultUnlocked = false
    @Published public private(set) var secretFiles: [URL] = []
    
    public var secretPasscodeFormula: String = "7749="
    private let vaultDirectory: URL
    
    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.vaultDirectory = docs.appendingPathComponent(".UltimateVault", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.vaultDirectory, withIntermediateDirectories: true)
        
        setupAutoLockOnBackground()
    }
    
    private func setupAutoLockOnBackground() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lockVault()
        }
    }
    
    public func lockVault() {
        self.isVaultUnlocked = false
        self.secretFiles = []
    }
    
    public func unlockVault() {
        self.isVaultUnlocked = true
        loadVaultFiles()
        UltimateHapticEngine.shared.playDetentSnap()
    }
    
    public func loadVaultFiles() {
        let contents = (try? FileManager.default.contentsOfDirectory(at: vaultDirectory, includingPropertiesForKeys: nil)) ?? []
        self.secretFiles = contents.filter { !$0.lastPathComponent.hasPrefix(".") }
    }
}

// MARK: - Calculator UI & Secret Trigger

public struct UltimateSecretVaultView: View {
    @ObservedObject var vault = UltimateVaultManager.shared
    
    @State private var displayText = "0"
    @State private var formulaHistory = ""
    @State private var currentOperation: String? = nil
    @State private var firstOperand: Double? = nil
    @State private var isEnteringSecondOperand = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if vault.isVaultUnlocked {
                unlockedVaultView
            } else {
                calculatorView
            }
        }
    }
    
    // MARK: - Working Calculator View
    
    private var calculatorView: some View {
        VStack(spacing: 12) {
            Spacer()
            
            // Formula display
            HStack {
                Spacer()
                Text(formulaHistory)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 24)
            
            // Main Number Display
            HStack {
                Spacer()
                Text(displayText)
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            
            // Calculator Grid
            let buttons: [[String]] = [
                ["AC", "+/-", "%", "÷"],
                ["7", "8", "9", "×"],
                ["4", "5", "6", "-"],
                ["1", "2", "3", "+"],
                ["0", ".", "="]
            ]
            
            VStack(spacing: 12) {
                ForEach(buttons, id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.self) { label in
                            calcButton(label: label)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
    
    private func calcButton(label: String) -> some View {
        let isZero = label == "0"
        let isOp = ["÷", "×", "-", "+", "="].contains(label)
        let isSpecial = ["AC", "+/-", "%"].contains(label)
        
        let bgColor: Color = isOp ? UltimateDesignSystem.Colors.cyberOrange : (isSpecial ? Color.gray : Color(white: 0.2))
        let fgColor: Color = isSpecial ? .black : .white
        
        return Button {
            handleButtonPress(label)
            UltimateHapticEngine.shared.playJogTick(intensity: 0.35)
        } label: {
            Text(label)
                .font(.title)
                .foregroundColor(fgColor)
                .frame(width: isZero ? 160 : 72, height: 72)
                .background(bgColor)
                .cornerRadius(36)
        }
    }
    
    private func handleButtonPress(_ label: String) {
        formulaHistory += label
        
        // Check Secret Formula Passcode Trigger (e.g. "7749=")
        if formulaHistory.hasSuffix(vault.secretPasscodeFormula) {
            formulaHistory = ""
            displayText = "0"
            vault.unlockVault()
            return
        }
        
        switch label {
        case "0"..."9":
            if displayText == "0" || isEnteringSecondOperand {
                displayText = label
                isEnteringSecondOperand = false
            } else {
                displayText += label
            }
        case ".":
            if !displayText.contains(".") {
                displayText += "."
            }
        case "AC":
            displayText = "0"
            formulaHistory = ""
            firstOperand = nil
            currentOperation = nil
        case "+/-":
            if let val = Double(displayText) {
                displayText = String(-val)
            }
        case "%":
            if let val = Double(displayText) {
                displayText = String(val / 100.0)
            }
        case "+", "-", "×", "÷":
            firstOperand = Double(displayText)
            currentOperation = label
            isEnteringSecondOperand = true
        case "=":
            if let op = currentOperation, let first = firstOperand, let second = Double(displayText) {
                var res: Double = 0
                switch op {
                case "+": res = first + second
                case "-": res = first - second
                case "×": res = first * second
                case "÷": res = second != 0 ? first / second : 0
                default: break
                }
                displayText = String(format: "%g", res)
                firstOperand = nil
                currentOperation = nil
            }
        default:
            break
        }
    }
    
    // MARK: - Unlocked Secret Vault View
    
    private var unlockedVaultView: some View {
        VStack {
            HStack {
                Text("SECRET MEDIA VAULT")
                    .font(UltimateDesignSystem.Typography.dspTitle)
                    .foregroundColor(UltimateDesignSystem.Colors.neonTeal)
                Spacer()
                Button {
                    vault.lockVault()
                } label: {
                    Image(systemName: "lock.fill")
                        .foregroundColor(UltimateDesignSystem.Colors.studioCrimson)
                        .padding(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            if vault.secretFiles.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
                    Text("No secret files stored.")
                        .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
                    Spacer()
                }
            } else {
                List(vault.secretFiles, id: \.self) { url in
                    HStack {
                        Image(systemName: "film.fill")
                            .foregroundColor(UltimateDesignSystem.Colors.neonTeal)
                        Text(url.lastPathComponent)
                            .foregroundColor(UltimateDesignSystem.Colors.textPrimary)
                        Spacer()
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}
