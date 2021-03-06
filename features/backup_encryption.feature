Feature: Encrypt backup files
  In order to be able to store my backups in the cloud
  As a backup operator
  I want Electric Sheep to encrypt files using public-key cryptography

  Background:
    Given I'm working on configuration "Sheepfile.encryption"

  Scenario: Encrypt a file locally
    Given a local file containing private data
    When I tell the sheep to work on job "encrypt-file-locally"
    Then the file should have been encrypted
    And I should be able to decrypt it back

  Scenario: Encrypt a file remotely
    Given a remote file containing private data in the job "encrypt-file-remotely"
    When I tell the sheep to work on job "encrypt-file-remotely"
    Then the file should have been encrypted
    And I should be able to decrypt it back
