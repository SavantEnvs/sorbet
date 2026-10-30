// Port of test/fuzz/fuzz_doc_symbols.cc: upstream's copy no longer compiles against the current
// LSP/payload APIs (and is only reachable as a `manual` cc_test), so the harness lives here.
#include "core/ErrorQueue.h"
#include "core/NullFlusher.h"
#include "main/lsp/LSPMessage.h"
#include "main/lsp/json_types.h"
#include "main/lsp/wrapper.h"
#include "payload/payload.h"
#include "spdlog/sinks/stdout_sinks.h"
#include "test/helpers/MockFileSystem.h"
#include <cstddef>
#include <cstdint>
#include <memory>

using namespace std;
using namespace sorbet;
using namespace sorbet::realmain::lsp;

namespace {
const auto console = [] {
    auto logger = spdlog::stdout_logger_mt("console");
    logger->set_level(spdlog::level::critical);
    return logger;
}();
const auto typeErrors = [] {
    auto logger = spdlog::stdout_logger_mt("typeErrors");
    logger->set_level(spdlog::level::critical);
    return logger;
}();
const string rootPath = "/tmp";
const string rootUri = fmt::format("file://{}", rootPath);
const string fileName = "file.rb";
const string filePath = fmt::format("{}/{}", rootPath, fileName);
const string fileUri = fmt::format("{}/{}", rootUri, fileName);

shared_ptr<realmain::options::Options> mkOpts(string_view contents) {
    auto opts = make_shared<realmain::options::Options>();
    opts->fs = make_shared<test::MockFileSystem>(rootPath);
    opts->fs->writeFile(filePath, contents);
    opts->rawInputDirNames.emplace_back(rootPath);
    opts->inputFileNames.emplace_back(filePath);
    return opts;
}

unique_ptr<core::GlobalState> mkGlobalState(const realmain::options::Options &opts) {
    auto gs = make_unique<core::GlobalState>(
        make_shared<core::ErrorQueue>(*typeErrors, *console, make_shared<core::NullFlusher>()));
    unique_ptr<const OwnedKeyValueStore> kvstore;
    payload::createInitialGlobalState(*gs, opts, kvstore);
    return gs;
}

unique_ptr<SingleThreadedLSPWrapper> mkLSPWrapper(string_view contents) {
    static const auto commonGs = [] {
        auto opts = mkOpts("");
        return mkGlobalState(*opts);
    }();
    auto lspWrapper =
        SingleThreadedLSPWrapper::createWithGlobalState(commonGs->deepCopyGlobalState(true), mkOpts(contents), console,
                                                        unique_ptr<KeyValueStore>());
    lspWrapper->enableAllExperimentalFeatures();
    return lspWrapper;
}
} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, const size_t size) {
    string contents((const char *)data, size);
    auto lspWrapper = mkLSPWrapper(contents);
    int nextId = 0;
    {
        auto initializeParams = make_unique<InitializeParams>(rootUri, make_unique<ClientCapabilities>());
        initializeParams->rootPath = rootPath;
        auto docCapabilities = make_unique<TextDocumentClientCapabilities>();
        auto documentSymbol = make_unique<DocumentSymbolCapabilities>();
        documentSymbol->dynamicRegistration = true;
        auto symbolKind = make_unique<SymbolKindOptions>();
        vector<SymbolKind> supportedSymbols;
        for (int i = (int)SymbolKind::File; i <= (int)SymbolKind::TypeParameter; i++) {
            supportedSymbols.push_back((SymbolKind)i);
        }
        symbolKind->valueSet = move(supportedSymbols);
        documentSymbol->symbolKind = move(symbolKind);
        docCapabilities->documentSymbol = move(documentSymbol);
        initializeParams->capabilities->textDocument = move(docCapabilities);
        initializeParams->trace = TraceKind::Off;
        lspWrapper->getLSPResponsesFor(make_unique<LSPMessage>(
            make_unique<RequestMessage>("2.0", nextId++, LSPMethod::Initialize, move(initializeParams))));
        lspWrapper->getLSPResponsesFor(make_unique<LSPMessage>(
            make_unique<NotificationMessage>("2.0", LSPMethod::Initialized, make_unique<InitializedParams>())));
    }
    auto responses = lspWrapper->getLSPResponsesFor(make_unique<LSPMessage>(make_unique<RequestMessage>(
        "2.0", nextId++, LSPMethod::TextDocumentDocumentSymbol,
        make_unique<DocumentSymbolParams>(make_unique<TextDocumentIdentifier>(fileUri)))));
    ENFORCE(responses.size() == 1);
    return 0;
}
