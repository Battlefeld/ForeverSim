import unittest
from blueposts import parse, compare


def feed(body='Damage increased', title='Forever Hotfixes'):
    return f'<rss><channel><item><guid>1</guid><title>{title}</title><link>https://us.forums.blizzard.com/test</link><description>{body}</description></item></channel></rss>'.encode()


class BluePostsTests(unittest.TestCase):
    def test_first_run_is_baseline_and_unchanged_feed_does_not_trigger(self):
        current = parse(feed())
        self.assertEqual(compare({}, current), [])
        self.assertEqual(compare({'posts': current}, current), [])

    def test_edit_of_existing_patch_post_is_detected(self):
        old = {'posts': parse(feed())}
        changes = compare(old, parse(feed('Damage reduced')))
        self.assertEqual(changes[0]['kind'], 'edited')
        self.assertTrue(changes[0]['relevant'])

    def test_empty_or_html_response_is_rejected(self):
        for raw in (b'<html>error</html>', b'<rss><channel/></rss>'):
            with self.assertRaises(ValueError): parse(raw)

if __name__ == '__main__': unittest.main()
