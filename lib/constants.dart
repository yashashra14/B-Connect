class Constants {
  static final List<UrlMapper> urlMapperList = [
    UrlMapper(
      title: 'C4C Dining 10%OFF',
      url:
          'https://www.colorado.edu/resources/center-community-c4c-dining-center',
    ),
    UrlMapper(
      title: '1B51 LP Project Demos',
      url: 'https://sites.google.com/view/lpprojectdemofall2025/home',
    ),
    UrlMapper(
      title: "Apple Career Event",
      url: "https://www.apple.com/careers/us/",
    ),
  ];
}

class UrlMapper {
  final String title;
  final String url;

  UrlMapper({required this.title, required this.url});
}
