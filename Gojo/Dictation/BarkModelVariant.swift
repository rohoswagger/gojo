import Foundation

enum BarkModelVariant: Sendable {
    case verbatim
    case clean

    var modelID: DictationModelID {
        self == .clean ? .underdogBark3CleanEnglish : .underdogBark3English
    }
    var repository: String {
        self == .clean ? "FluidInference/bark-3.0-coreml" : "ConwayResearch/Underdog-Bark-3.0"
    }
    var revision: String {
        self == .clean ? "73b0c0da665d29ea0332e9f0d32da8e26a4cdb38" : BarkSpeechRuntime.revision
    }
    var cachedModelFolderKey: String {
        "gojo.dictation.modelFolder.\(self == .clean ? "bark-3.0-clean" : "bark-3.0").\(revision)"
    }
    var maximumModelBytes: UInt64 { self == .clean ? 447_420_698 : 202_204_000 }
    var runtimeSubdirectory: String { self == .clean ? "bark-3.0-clean" : "coreml/ane" }
    var removalItems: [String] { self == .clean ? ["bark-3.0-clean"] : ["coreml"] }
    var modelSHA256: [String: String] { self == .clean ? Self.cleanSHA256 : Self.verbatimSHA256 }
    var downloadPatterns: [String] { Array(modelSHA256.keys) }

    private static let verbatimSHA256: [String: String] = [
        "coreml/ane/BarkEncoder.mlpackage/Data/com.apple.CoreML/model.mlmodel": "7c3f1c1612ba21bcc4d8efff1b32154b39cb3e1e2f10020117793acc5c96fcdf",
        "coreml/ane/BarkEncoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin": "98979e5dd731486ddfb2c312f80a3038205c058aac9fe0f403ba26e1a158d385",
        "coreml/ane/BarkEncoder.mlpackage/Manifest.json": "d37c121561b99da49b9bf1e28c00152c14c56a943815fa83008ee0691b8f1149",
        "coreml/ane/decoder.npz": "1ce79071f54c3dcec9aa9bb1d488486766f1fdbb3fd988b776da3f4da8024665",
        "coreml/ane/vocab.json": "eee86951e9f74921342fdc60ba26711eb70f7188e8784d98d2aecfc525b72270",
    ]

    private static let cleanSHA256: [String: String] = [
        "bark-3.0-clean/Decoder.mlmodelc/analytics/coremldata.bin": "d00e8baa4b1d7fc164d7cbbb96ed294d531ba6fb684a1aa79f66d4e4fbdbd5da",
        "bark-3.0-clean/Decoder.mlmodelc/coremldata.bin": "b33a57a008e7b138574bac1219037aadd7054caebfc42d0fa4adc97050f6a836",
        "bark-3.0-clean/Decoder.mlmodelc/metadata.json": "de3e22da7619f1ba9ae8ab3676ece49a999b93b3ca2a6653687c54b0e69419fc",
        "bark-3.0-clean/Decoder.mlmodelc/model.mil": "34bd2cc0a00dd7a485f0aa90f58d6b516c94ee8f4842de92aad7b581849df289",
        "bark-3.0-clean/Decoder.mlmodelc/weights/weight.bin": "6220cd08cb7eaacf5106da134c40f57e13783342c09f1be250dd31cc1b8b8a94",
        "bark-3.0-clean/Encoder.mlmodelc/analytics/coremldata.bin": "8f6763508e0d6caad8152bcc72cf8be1647f568c3cdc5c5ff9732c1c69e2734c",
        "bark-3.0-clean/Encoder.mlmodelc/coremldata.bin": "e08f511d23e5642bc45f6ecc0bc930e00f8f105d6a6c33fe03f83c8da9253070",
        "bark-3.0-clean/Encoder.mlmodelc/model.mil": "0442825ac24b17cd861db7a8bda7cda16c3372c8228331e640196965f190583d",
        "bark-3.0-clean/Encoder.mlmodelc/weights/weight.bin": "4216107d2214bd058aec94c2e0f9a7e8114f5274cf0c6a28ffb8f21ea56337eb",
        "bark-3.0-clean/JointDecisionv3.mlmodelc/analytics/coremldata.bin": "a55f011ca119fc7913ffc905ef48079572c4f54b6e5ed34a033f69c5422be0b6",
        "bark-3.0-clean/JointDecisionv3.mlmodelc/coremldata.bin": "2f5d97969689b6397b8f2e8ba31a1d4684a41ec373ecf56d4ee751efb2ca5073",
        "bark-3.0-clean/JointDecisionv3.mlmodelc/metadata.json": "989223d0134de212bb206b7311b9f7038d26f86d0d43a88b17deee895d0a931e",
        "bark-3.0-clean/JointDecisionv3.mlmodelc/model.mil": "167357ff6d558349e745047c6e3f610010d047ec21ab6f56df2dbb041f096baa",
        "bark-3.0-clean/JointDecisionv3.mlmodelc/weights/weight.bin": "4575e6ec06917259358cf17307fe7aa38d364b736e4b6c9b6e3d49169c760eee",
        "bark-3.0-clean/NOTICE": "4e627d41fa10efedd84a7dbb915711b0b73c904af1fee8bacdd4a2387bcc5a10",
        "bark-3.0-clean/Preprocessor.mlmodelc/analytics/coremldata.bin": "c9beeb989c8d66f8be11df59bc6df277ec76cee404f6865b46243835ef562f6d",
        "bark-3.0-clean/Preprocessor.mlmodelc/coremldata.bin": "dbde3f2300842c1fd51ef3ff948a0bcffe65ffd2dca10707f2509f32c1d65b1d",
        "bark-3.0-clean/Preprocessor.mlmodelc/metadata.json": "2a98699e22d279dd37fa1d238aeb1c6db1df0d6fad687775324157689d8f3acf",
        "bark-3.0-clean/Preprocessor.mlmodelc/model.mil": "4b8518a956450fec57f06c2a21bdffc26973f7f1fa6842fb38fe917f896b6b93",
        "bark-3.0-clean/Preprocessor.mlmodelc/weights/weight.bin": "129b76e3aeafa8afa3ea76d995b964b145fe83700d579f6ff42c4c38fa0968ea",
        "bark-3.0-clean/parakeet_vocab.json": "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735",
    ]
}
