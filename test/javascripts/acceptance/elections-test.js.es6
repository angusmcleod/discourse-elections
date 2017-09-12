import { acceptance } from "helpers/qunit-helpers";
import { angus } from '../fixtures/session';
import { nominationTopic, electionTopic } from '../fixtures/topics';

function logInAngus() {
  Discourse.User.resetCurrent(Discourse.User.create(angus));
}

acceptance("Elections", {
  beforeEach: logInAngus,
});

test("Nomination", (assert) => {
  server.get('/t/36.json', () => { // eslint-disable-line no-undef
    return nominationTopic;
  });

  visit("/t/36");

  andThen(() => {
    assert.equal(find('.election-status span').text(), 'Taking Nominations', 'it should render the nomination election status');
    assert.equal(find('.election-controls button').length, 4, 'it should render the nomination election controls');
    assert.equal(find('.nomination').length, 2, 'it should render the nominations');
    assert.equal(find('.nomination-statement').length, 2, 'it should render the nomination statements');
    assert.equal(find('.statement-post-label').length, 1, 'it should render the post nomination statement labels');
    assert.equal(find('.avatar-flair.nominee').length, 1, 'it should render the nominee avatar flairs');
  });

  click('.toggle-nomination');

  andThen(() => {
    assert.ok(exists('.confirm-nomination'), 'it should render the confirm nomination modal');
  });

  click('.add-statement');

  andThen(() => {
    assert.ok(exists('#reply-control'), 'it should render the composer');
    assert.ok(exists('.statement-composer-label'), 'it should render the nomination statement composer label');
  });

  click('.manage-election');

  andThen(() => {
    assert.ok(exists('.manage-election'), 'it should render the manage election modal');
  });
});

test("Poll", (assert) => {
  server.get('/t/35.json', () => { // eslint-disable-line no-undef
    return electionTopic;
  });

  visit("/t/35");

  andThen(() => {
    assert.equal(find('.election-status span').text(), 'Electing', 'it should render the poll election status');
    assert.equal(find('.nomination').length, 3, 'it should render the nominations');
  });
});
