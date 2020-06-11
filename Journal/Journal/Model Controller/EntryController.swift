//
//  EntryController.swift
//  Journal
//
//  Created by Clayton Watkins on 6/10/20.
//  Copyright © 2020 Clayton Watkins. All rights reserved.
//

import Foundation
import CoreData

// To handle network call errors
enum NetworkError: Error{
    case noIdentifier
    case otherError
    case noData
    case noDecode
    case noEncode
    case noRep
}

// The base URL for our database
var baseURL = URL(string: "https://journal-26adb.firebaseio.com/")!

class EntryController {
    
    // MARK: - Properties
    typealias CompletionHandler = (Result<Bool, NetworkError>) -> Void
    
    // MARK: - Initializer
    init(){
        fetchEntriesFromServer()
    }
    
    // MARK: - Network Functions
    
    //This will send our entries to our server
    func sendEntryToServer(entry: Entry, completion: @escaping CompletionHandler = { _ in }){
        guard let uuid = entry.identifier else {
            completion(.failure(.noIdentifier))
            return
        }
        
        let requestURL = baseURL.appendingPathComponent(uuid).appendingPathExtension("json")
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "PUT"
        
        do{
            guard let representation = entry.entryRepresentation else {
                completion(.failure(.noRep))
                return
            }
            request.httpBody = try JSONEncoder().encode(representation)
        } catch {
            print("Error encoding task \(entry): \(error)")
            completion(.failure(.noEncode))
        }
        
        URLSession.shared.dataTask(with: request) { (data, _, error) in
            if let error = error{
                completion(.failure(.otherError))
                print("Error putting task to server: \(error)")
                return
            }
            
            DispatchQueue.main.async {
                completion(.success(true))
            }
        }.resume()
    }
    
    // This allows us to delete our entry from the database
    func deleteEntryFromServer(entry: Entry, completion: @escaping CompletionHandler = { _ in }){
        guard let uuid = entry.identifier else {
            completion(.failure(.noIdentifier))
            return
        }
        let requestURL = baseURL.appendingPathComponent(uuid).appendingPathExtension("json")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "DELETE"
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            print(response!)
            DispatchQueue.main.async {
                completion(.success(true))
            }
        }.resume()
    }
    
    // This will allow us to pull entries from our database
    func fetchEntriesFromServer(completion: @escaping CompletionHandler = { _ in }){
        let requestURL = baseURL.appendingPathExtension("json")
        
        URLSession.shared.dataTask(with: requestURL) { (data, _, error) in
            if let error = error{
                print("Error fetching tasks: \(error)")
                completion(.failure(.otherError))
                return
            }
            
            guard let data = data else{
                print("No data returned by task")
                completion(.failure(.noData))
                return
            }
            
            do{
                let taskRepresentation = Array(try JSONDecoder().decode([String : EntryRepresentation].self, from: data).values)
                try self.updateTasks(with: taskRepresentation)
                completion(.success(true))
            } catch {
                print("Error decoding task representation: \(error)")
                completion(.failure(.noDecode))
            }
        }.resume()
    }
    
    
    // MARK: - Private Functions
    
    // Here we are setting our entries properties to a representation so that we can use it to check if we are reciving unique values from the server, or if they already exist in our persistent store
    private func update(entry: Entry, with representation: EntryRepresentation){
        entry.title = representation.title
        entry.bodyText = representation.bodyText
        entry.timestamp = representation.timestamp
        entry.mood = representation.mood
    }
    
    private func updateTasks(with representations: [EntryRepresentation]) throws {
        let context = CoreDataStack.shared.container.newBackgroundContext()
        // Creating an array of UUIDs
        let identifiersToFetch = representations.compactMap({ $0.identifier })
        // Creating Dictionaries of our representations by create a key value pair of UUID : representattion
        let representationsByID = Dictionary(uniqueKeysWithValues: zip(identifiersToFetch, representations))
        var tasksToCreate = representationsByID
        let fetchRequest: NSFetchRequest<Entry> = Entry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "identifier IN %@", identifiersToFetch)
        context.performAndWait {
            do{
                let existingTasks = try context.fetch(fetchRequest)
                
                // For already existing tasks
                for entry in existingTasks{
                    guard let id = entry.identifier,
                        let representation = representationsByID[id] else { continue }
                    // Update Task
                    self.update(entry: entry, with: representation)
                    tasksToCreate.removeValue(forKey: id)
                }
                
                for representation in tasksToCreate.values{
                    Entry(entryRepresentation: representation, context: context)
                }
            } catch {
                print("Error fetching tasks for UUIDs: \(error)")
            }
        }
        try CoreDataStack.shared.save(context: context)
    }
}
