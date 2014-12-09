//
//  Objects.swift
//  SwiftGit2
//
//  Created by Matt Diephouse on 12/4/14.
//  Copyright (c) 2014 GitHub, Inc. All rights reserved.
//

import Foundation

/// The types of git objects.
public enum ObjectType: Equatable {
	case Commit
	case Tree
	case Blob
	case Tag
	
	static func fromLibgit2Type(type: git_otype) -> ObjectType? {
		switch type.value {
		case GIT_OBJ_COMMIT.value:
			return .Commit
		case GIT_OBJ_TREE.value:
			return .Tree
		case GIT_OBJ_BLOB.value:
			return .Blob
		case GIT_OBJ_TAG.value:
			return .Tag
		default:
			return nil
		}
	}
}

extension ObjectType: Printable {
	public var description: String {
		switch self {
		case .Commit:
			return "commit"
		case .Tree:
			return "tree"
		case .Blob:
			return "blob"
		case .Tag:
			return "tag"
		}
	}
}

public func == (lhs: ObjectType, rhs: ObjectType) -> Bool {
	switch (lhs, rhs) {
	case (.Commit, .Commit), (.Tree, .Tree), (.Blob, .Blob), (.Tag, .Tag):
		return true
	default:
		return false
	}
}

/// A git object.
public protocol Object {
	/// The OID of the object.
	var oid: OID { get }
}

public struct Signature {
	/// The name of the person.
	public let name: String
	
	/// The email of the person.
	public let email: String
	
	/// The time when the action happened.
	public let time: NSDate
	
	/// The time zone that `time` should be interpreted relative to.
	public let timeZone: NSTimeZone
	
	/// Create an instance with a libgit2 `git_signature`.
	public init(signature: git_signature) {
		name = String.fromCString(signature.name)!
		email = String.fromCString(signature.email)!
		time = NSDate(timeIntervalSince1970: NSTimeInterval(signature.when.time))
		timeZone = NSTimeZone(forSecondsFromGMT: NSInteger(60 * signature.when.offset))
	}
}

extension Signature: Hashable {
	public var hashValue: Int {
		return name.hashValue ^ email.hashValue ^ Int(time.timeIntervalSince1970)
	}
}

public func == (lhs: Signature, rhs: Signature) -> Bool {
	return lhs.name == rhs.name
		&& lhs.email == rhs.email
		&& lhs.time == rhs.time
		&& lhs.timeZone.secondsFromGMT == rhs.timeZone.secondsFromGMT
}

/// A git commit.
public struct Commit: Object {
	/// The OID of the commit.
	public let oid: OID
	
	/// The OID of the commit's tree.
	public let tree: OID
	
	/// The OIDs of the commit's parents.
	public let parents: [OID]
	
	/// The author of the commit.
	public let author: Signature
	
	/// The committer of the commit.
	public let committer: Signature
	
	/// The full message of the commit.
	public let message: String
	
	/// Create an instance with a libgit2 `git_commit` object.
	public init(pointer: COpaquePointer) {
		oid = OID(oid: git_object_id(pointer).memory)
		message = String.fromCString(git_commit_message(pointer))!
		author = Signature(signature: git_commit_author(pointer).memory)
		committer = Signature(signature: git_commit_committer(pointer).memory)
		tree = OID(oid: git_commit_tree_id(pointer).memory)
		
		var parents: [OID] = []
		for idx in 0..<git_commit_parentcount(pointer) {
			let oid = git_commit_parent_id(pointer, idx).memory
			parents.append(OID(oid: oid))
		}
		self.parents = parents
	}
}

extension Commit: Hashable {
	public var hashValue: Int {
		return self.oid.hashValue
	}
}

public func == (lhs: Commit, rhs: Commit) -> Bool {
	return lhs.oid == rhs.oid
}

/// A git tree.
public struct Tree: Object {
	/// An entry in a `Tree`.
	public struct Entry {
		/// The entry's UNIX file attributes.
		public let attributes: Int
		
		/// The type of object pointed to by the entry.
		public let type: ObjectType
		
		/// The OID of the object pointed to by the entry.
		public let oid: OID
		
		/// The file name of the entry.
		public let name: String
		
		/// Create an instance with a libgit2 `git_tree_entry`.
		public init(pointer: COpaquePointer) {
			attributes = Int(git_tree_entry_filemode(pointer).value)
			type = ObjectType.fromLibgit2Type(git_tree_entry_type(pointer))!
			oid = OID(oid: git_tree_entry_id(pointer).memory)
			name = String.fromCString(git_tree_entry_name(pointer))!
		}
		
		/// Create an instance with the individual values.
		public init(attributes: Int, type: ObjectType, oid: OID, name: String) {
			self.attributes = attributes
			self.type = type
			self.oid = oid
			self.name = name
		}
	}

	/// The OID of the tree.
	public let oid: OID
	
	/// The entries in the tree.
	public let entries: [String: Entry]
	
	/// Create an instance with a libgit2 `git_tree`.
	public init(pointer: COpaquePointer) {
		oid = OID(oid: git_object_id(pointer).memory)
		
		var entries: [String: Entry] = [:]
		for idx in 0..<git_tree_entrycount(pointer) {
			let entry = Entry(pointer: git_tree_entry_byindex(pointer, idx))
			entries[entry.name] = entry
		}
		self.entries = entries
	}
}

extension Tree.Entry: Hashable {
	public var hashValue: Int {
		return attributes ^ oid.hashValue ^ name.hashValue
	}
}

extension Tree.Entry: Printable {
	public var description: String {
		return "\(attributes) \(type) \(oid) \(name)"
	}
}

public func == (lhs: Tree.Entry, rhs: Tree.Entry) -> Bool {
	return lhs.attributes == rhs.attributes
		&& lhs.type == rhs.type
		&& lhs.oid == rhs.oid
		&& lhs.name == rhs.name
}

extension Tree: Hashable {
	public var hashValue: Int {
		return oid.hashValue
	}
}

public func == (lhs: Tree, rhs: Tree) -> Bool {
	return lhs.oid == rhs.oid
}

/// A git blob.
public struct Blob: Object {
	/// The OID of the blob.
	public let oid: OID
	
	/// The contents of the blob.
	public let data: NSData
	
	/// Create an instance with a libgit2 `git_blob`.
	public init(pointer: COpaquePointer) {
		oid = OID(oid: git_object_id(pointer).memory)
		
		// Swift doesn't get the types right without `Int(Int64(...))` :(
		let length = Int(Int64(git_blob_rawsize(pointer).value))
		data = NSData(bytes: git_blob_rawcontent(pointer), length: length)
	}
}

extension Blob: Hashable {
	public var hashValue: Int {
		return oid.hashValue
	}
}

public func == (lhs: Blob, rhs: Blob) -> Bool {
	return lhs.oid == rhs.oid
}
