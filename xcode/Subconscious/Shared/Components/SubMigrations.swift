//
//  SubMigrations.swift
//  Subconscious (iOS)
//
//  Created by Gordon Brander on 7/12/21.
//

let SUB_MIGRATIONS = SQLite3Migrations([
    SQLite3Migrations.Migration(
        date: "2021-07-01T15:43:00",
        sql: """
        CREATE TABLE search_history (
            id TEXT PRIMARY KEY,
            query TEXT NOT NULL,
            hits INTEGER NOT NULL,
            created TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE entry (
          path TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          body TEXT NOT NULL,
          modified TEXT NOT NULL,
          size INTEGER NOT NULL
        );

        CREATE VIRTUAL TABLE entry_search USING fts5(
          path UNINDEXED,
          title,
          body,
          modified UNINDEXED,
          size UNINDEXED,
          content="entry",
          tokenize="porter"
        );

        /*
        Create triggers to keep fts5 virtual table in sync with content table.

        Note: SQLite documentation notes that you want to modify the fts table *before*
        the external content table, hence the BEFORE commands.

        These triggers are adapted from examples in the docs:
        https://www.sqlite.org/fts3.html#_external_content_fts4_tables_
        */
        CREATE TRIGGER entry_search_before_update BEFORE UPDATE ON entry BEGIN
          DELETE FROM entry_search WHERE rowid=old.rowid;
        END;

        CREATE TRIGGER entry_search_before_delete BEFORE DELETE ON entry BEGIN
          DELETE FROM entry_search WHERE rowid=old.rowid;
        END;

        CREATE TRIGGER entry_search_after_update AFTER UPDATE ON entry BEGIN
          INSERT INTO entry_search
            (
              rowid,
              path,
              title,
              body,
              modified,
              size
            )
          VALUES
            (
              new.rowid,
              new.path,
              new.title,
              new.body,
              new.modified,
              new.size
            );
        END;

        CREATE TRIGGER entry_search_after_insert AFTER INSERT ON entry BEGIN
          INSERT INTO entry_search
            (
              rowid,
              path,
              title,
              body,
              modified,
              size
            )
          VALUES
            (
              new.rowid,
              new.path,
              new.title,
              new.body,
              new.modified,
              new.size
            );
        END;
        """
    )!
])!