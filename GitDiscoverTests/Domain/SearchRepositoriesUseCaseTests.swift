import Testing
@testable import GitDiscover

struct SearchRepositoriesUseCaseTests {
    @Test func validQueryDelegatesAndReturnsRepositories() async throws {
        let repositories = [try makeRepository()]
        let spy = RepositorySpy(result: .success(repositories))
        let useCase = SearchRepositoriesUseCase(repository: spy)

        let result = try await useCase.execute(query: "swift")

        #expect(result == repositories)
        #expect(await spy.queries == ["swift"])
    }

    @Test func surroundingWhitespaceIsTrimmedWithoutChangingExpression() async throws {
        let spy = RepositorySpy()
        let useCase = SearchRepositoriesUseCase(repository: spy)

        _ = try await useCase.execute(query: " \n Swift  language:Swift \t")

        #expect(await spy.queries == ["Swift  language:Swift"])
    }

    @Test(arguments: ["", "  ", "a", " a ", "\n\t"])
    func invalidQueryDoesNotInvokeRepository(query: String) async throws {
        let spy = RepositorySpy()
        let useCase = SearchRepositoriesUseCase(repository: spy)

        #expect(try await useCase.execute(query: query).isEmpty)
        #expect(await spy.queries.isEmpty)
    }

    @Test func repositoryErrorPropagates() async {
        let spy = RepositorySpy(result: .failure(TestFailure.offline))
        let useCase = SearchRepositoriesUseCase(repository: spy)

        await #expect(throws: TestFailure.offline) {
            try await useCase.execute(query: "swift")
        }
    }

    @Test func cancellationErrorPropagates() async {
        let spy = RepositorySpy(result: .failure(CancellationError()))
        let useCase = SearchRepositoriesUseCase(repository: spy)

        await #expect(throws: CancellationError.self) {
            try await useCase.execute(query: "swift")
        }
    }
}