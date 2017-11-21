import { registerUnbound } from 'discourse-common/lib/helpers';
import { formatTime } from '../lib/election';

export default registerUnbound('election-time', function(time) {
  return new Handlebars.SafeString(formatTime(time));
});
