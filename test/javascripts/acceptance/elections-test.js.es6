import { acceptance } from "helpers/qunit-helpers";
import angus from '../fixtures/session';
import { nominationTopic, pollTopic } from '../fixtures/topics';

function logInAngus() {
  Discourse.User.resetCurrent(Discourse.User.create(angus['/session/current.json'].current_user));
}

acceptance("Elections", {
  beforeEach: logInAngus,
  settings: { elections_enabled: true, elections_nominee_avatar_flair: 'certificate' }
});

test("Nomination", (assert) => {
  server.get('/t/46.json', () => { // eslint-disable-line no-undef
    return nominationTopic;
  });

  visit("/t/president-election/46");

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
  server.get('/t/46.json', () => { // eslint-disable-line no-undef
    return pollTopic;
  });

  visit("/t/president-election/46");

  andThen(() => {
    assert.equal(find('.election-status span').text(), 'Poll Open', 'it should render the poll election status');
    assert.equal(find('.nomination').length, 2, 'it should render the nominations');
  });
});
